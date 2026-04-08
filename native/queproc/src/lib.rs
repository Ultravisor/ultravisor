// SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

use parking_lot::Mutex;
use std::collections::{BTreeMap, VecDeque};
use std::time::Instant;

use rustler::{Env, LocalPid};

rustler::atoms! {
    worker,
    wait,
    closed,
    worker_available,
    queue_closed,
    more_power,
}

#[derive(PartialEq)]
enum WorkerStatus {
    Leased,
    Available(Instant),
    Dispatching(Waiter),
}

struct Worker {
    monitor: rustler::Monitor,
    status: WorkerStatus,
}

impl Worker {
    fn into_waiter(self) -> Option<Waiter> {
        match self.status {
            WorkerStatus::Dispatching(waiter) => Some(waiter),
            _ => None,
        }
    }

    /// Set new worker status
    ///
    /// Return previous status of the worker
    fn set_status(&mut self, new_status: WorkerStatus) -> WorkerStatus {
        std::mem::replace(&mut self.status, new_status)
    }

    fn is_monitored_by(&self, monitor: rustler::Monitor) -> bool {
        match self.status {
            WorkerStatus::Dispatching(ref waiter) => waiter.monitor == monitor,
            _ => false,
        }
    }

    fn is_waited_by(&self, waiter_id: u64) -> bool {
        match self.status {
            WorkerStatus::Dispatching(ref w) => w.id == waiter_id,
            _ => false,
        }
    }
}

#[derive(PartialEq)]
struct Waiter {
    id: u64,
    pid: LocalPid,
    monitor: rustler::Monitor,
}

struct State {
    closed: bool,
    next_waiter_id: u64,
    workers: BTreeMap<LocalPid, Worker>,
    available: VecDeque<LocalPid>,
    waiters: VecDeque<Waiter>,
}

struct Queproc {
    owner: LocalPid,
    state: Mutex<State>,
}

impl std::panic::RefUnwindSafe for Queproc {}

#[rustler::resource_impl]
impl rustler::Resource for Queproc {
    fn down(&self, env: Env, _pid: LocalPid, monitor: rustler::Monitor) {
        let mut reclaimed = None;
        {
            let State {
                ref mut workers,
                ref mut available,
                ref mut waiters,
                ..
            } = *self.state.lock();

            if let Some((pid, worker)) = workers.extract_if(.., |_, w| w.monitor == monitor).next()
            {
                available.retain(|p| p != &pid);
                if let WorkerStatus::Dispatching(waiter) = worker.status {
                    waiters.push_front(waiter);
                    reclaimed = Some(pid);
                }
            } else if let Some(index) = waiters.iter().position(|w| w.monitor == monitor) {
                waiters.remove(index);
            } else if let Some((pid, worker)) =
                workers.iter_mut().find(|(_, w)| w.is_monitored_by(monitor))
                && let WorkerStatus::Dispatching(_waiter) = worker.set_status(WorkerStatus::Leased)
            {
                reclaimed = Some(*pid);
            }
        }

        if let Some(worker_pid) = reclaimed {
            route(env, self, worker_pid)
        }
    }
}

#[rustler::nif]
fn new<'a>(env: Env<'a>) -> rustler::ResourceArc<Queproc> {
    rustler::ResourceArc::new(Queproc {
        owner: env.pid(),
        state: Mutex::new(State {
            closed: false,
            next_waiter_id: 0,
            workers: Default::default(),
            available: VecDeque::new(),
            waiters: VecDeque::new(),
        }),
    })
}

#[rustler::nif]
fn insert(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) -> bool {
    {
        let mut state = queue.state.lock();
        if state.closed || state.workers.contains_key(&pid) {
            return false;
        }
        let Some(monitor) = queue.monitor(Some(env), &pid) else {
            return false;
        };
        state.workers.insert(
            pid,
            Worker {
                monitor,
                status: WorkerStatus::Leased,
            },
        );
    }
    route(env, &queue, pid);
    true
}

#[rustler::nif]
fn checkout<'a>(
    env: Env<'a>,
    queue: rustler::ResourceArc<Queproc>,
) -> (rustler::Atom, Option<LocalPid>, u64) {
    let mut state = queue.state.lock();
    if state.closed {
        (closed(), None, 0)
    } else if let Some(pid) = state.available.pop_back() {
        // We can unwrap there, as there **must** be worker for PID in available queue
        state
            .workers
            .get_mut(&pid)
            .unwrap()
            .set_status(WorkerStatus::Leased);

        (worker(), Some(pid), 0)
    } else {
        let monitor = queue
            .monitor(Some(env), &env.pid())
            .expect("caller monitor");
        state.next_waiter_id = state.next_waiter_id.wrapping_add(1);
        if state.next_waiter_id == 0 {
            state.next_waiter_id = 1;
        }
        let id = state.next_waiter_id;
        state.waiters.push_back(Waiter {
            id,
            pid: env.pid(),
            monitor,
        });
        let _ = env.send(&queue.owner, more_power());
        (wait(), None, id)
    }
}

#[rustler::nif]
fn checkin(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) {
    route(env, &queue, pid)
}

fn route(env: Env, queue: &Queproc, pid: LocalPid) {
    let State {
        workers,
        waiters,
        available,
        closed,
        ..
    } = &mut *queue.state.lock();
    if *closed {
        return;
    }
    let Some(worker) = workers.get_mut(&pid) else {
        return;
    };

    if worker.status != WorkerStatus::Leased {
        return;
    }

    if let Some(waiter) = waiters.pop_front() {
        let _ = env.send(&waiter.pid, (worker_available(), waiter.id, pid));
        worker.status = WorkerStatus::Dispatching(waiter);
    } else {
        worker.status = WorkerStatus::Available(Instant::now());
        available.push_back(pid);
    };
}

#[rustler::nif]
fn cleanup(queue: rustler::ResourceArc<Queproc>, size: usize, idle_timeout: u128) -> Vec<LocalPid> {
    let State {
        ref mut workers,
        ref mut available,
        ref waiters,
        ..
    } = *queue.state.lock();

    // If we have any process waiting, then we should not kill process that can be assigned to it
    // soon. So instead skip that many workers.
    let mut size = size.saturating_sub(waiters.len());

    let mut removed = vec![];

    available.retain(|pid| {
        if size == 0 {
            return true;
        }

        size -= 1;

        let worker = workers
            .remove(pid)
            .expect("There should always be existing worker for available PID");

        match worker.status {
            WorkerStatus::Available(since) if since.elapsed().as_millis() > idle_timeout => {
                removed.push(*pid);
                false
            }
            _ => {
                workers.insert(*pid, worker);
                true
            }
        }
    });

    removed
}

#[rustler::nif]
fn accept(env: Env, queue: rustler::ResourceArc<Queproc>, waiter_id: u64) -> bool {
    let mut state = queue.state.lock();
    if state.closed {
        return false;
    }
    let Some(worker) = state
        .workers
        .iter_mut()
        .find_map(|(_, worker)| match &worker.status {
            WorkerStatus::Dispatching(w) if w.id == waiter_id => Some(worker),
            _ => None,
        })
    else {
        return false;
    };

    match worker.set_status(WorkerStatus::Leased) {
        WorkerStatus::Dispatching(waiter) => {
            queue.demonitor(Some(env), &waiter.monitor);
            true
        }
        other => {
            worker.status = other;
            false
        }
    }
}

#[rustler::nif]
fn cancel_wait(env: Env, queue: rustler::ResourceArc<Queproc>, waiter_id: u64) {
    let mut state = queue.state.lock();
    if state.closed {
        return;
    }

    if let Some(index) = state.waiters.iter().position(|w| w.id == waiter_id) {
        queue.demonitor(Some(env), &state.waiters.remove(index).unwrap().monitor);
    } else if let Some((pid, worker)) = state
        .workers
        .iter_mut()
        .find(|(_, worker)| worker.is_waited_by(waiter_id))
        && let WorkerStatus::Dispatching(waiter) = worker.set_status(WorkerStatus::Leased)
    {
        queue.demonitor(Some(env), &waiter.monitor);
        route(env, &queue, *pid);
    }
}

#[rustler::nif]
fn close(env: Env, queue: rustler::ResourceArc<Queproc>) {
    let State {
        workers,
        waiters,
        closed,
        ..
    } = &mut *queue.state.lock();
    if *closed {
        return;
    }
    *closed = true;

    let mut drain = BTreeMap::new();

    // Replace the existing map with empty one to avoid ownership issues
    std::mem::swap(&mut drain, workers);

    let workers = drain.into_values().flat_map(|worker| {
        queue.demonitor(Some(env), &worker.monitor);

        worker.into_waiter()
    });
    for waiter in waiters.drain(..).chain(workers) {
        queue.demonitor(Some(env), &waiter.monitor);

        let _ = env.send(&waiter.pid, (queue_closed(), waiter.id));
    }
}

#[rustler::nif]
fn to_list(queue: &Queproc) -> Vec<LocalPid> {
    let state = queue.state.lock();
    state.workers.keys().copied().collect()
}

#[rustler::nif]
fn size(queue: &Queproc) -> usize {
    queue.state.lock().workers.len()
}

#[rustler::nif]
fn stats(queue: &Queproc) -> (LocalPid, usize, usize, usize) {
    let state = queue.state.lock();
    (
        queue.owner,
        state.available.len(),
        state.workers.len(),
        state.waiters.len(),
    )
}

rustler::init!("Elixir.Queproc.Native");
