// SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

//! Runtime-agnostic worker queue state machine.
//!
//! The NIF glue in [`crate`] implements [`Runtime`] on top of a running BEAM.
//! Tests implement the same traits over plain values, so the whole state
//! machine can be exercised with `cargo test` without an Erlang VM.

use std::collections::{BTreeMap, VecDeque};
use std::time::Instant;

/// Messages the queue sends to processes it tracks.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Message<P> {
    /// The queue has no free worker and the caller must wait.
    MorePower,
    /// A worker became available for a specific waiter.
    WorkerAvailable { waiter_id: u64, worker: P },
    /// The queue was closed while the caller was waiting.
    QueueClosed { waiter_id: u64 },
}

/// Sending side of the runtime.
pub trait Sender {
    type Pid: Copy;

    fn send(&self, pid: Self::Pid, message: Message<Self::Pid>);
}

/// Monitoring side of the runtime.
pub trait Runtime: Sender {
    type Monitor: Copy + PartialEq;

    fn monitor(&self, pid: Self::Pid) -> Option<Self::Monitor>;
    fn demonitor(&self, monitor: Self::Monitor);
}

#[derive(PartialEq)]
pub struct Waiter<P, M> {
    pub id: u64,
    pub pid: P,
    pub monitor: M,
}

#[derive(PartialEq)]
pub enum WorkerStatus<P, M> {
    Leased,
    Available(Instant),
    Dispatching(Waiter<P, M>),
}

pub struct Worker<P, M> {
    pub monitor: M,
    pub status: WorkerStatus<P, M>,
}

impl<P, M> Worker<P, M> {
    fn into_waiter(self) -> Option<Waiter<P, M>> {
        match self.status {
            WorkerStatus::Dispatching(waiter) => Some(waiter),
            _ => None,
        }
    }

    /// Set new worker status
    ///
    /// Return previous status of the worker
    fn set_status(&mut self, new_status: WorkerStatus<P, M>) -> WorkerStatus<P, M> {
        std::mem::replace(&mut self.status, new_status)
    }

    fn is_monitored_by(&self, monitor: M) -> bool
    where
        M: PartialEq,
    {
        match &self.status {
            WorkerStatus::Dispatching(waiter) => waiter.monitor == monitor,
            _ => false,
        }
    }

    fn is_waited_by(&self, waiter_id: u64) -> bool {
        match &self.status {
            WorkerStatus::Dispatching(w) => w.id == waiter_id,
            _ => false,
        }
    }
}

/// Outcome of [`State::checkout`].
#[derive(Debug, PartialEq, Eq)]
pub enum Checkout<P> {
    /// The queue is closed.
    Closed,
    /// A worker was handed to the caller.
    Worker(P),
    /// No worker is available; the caller waits with the given waiter id.
    Wait(u64),
}

pub struct State<P, M> {
    pub closed: bool,
    pub next_waiter_id: u64,
    pub workers: BTreeMap<P, Worker<P, M>>,
    pub available: VecDeque<P>,
    pub waiters: VecDeque<Waiter<P, M>>,
}

impl<P, M> Default for State<P, M>
where
    P: Copy + Ord,
    M: Copy + PartialEq,
{
    fn default() -> Self {
        Self::new()
    }
}

impl<P, M> State<P, M>
where
    P: Copy + Ord,
    M: Copy + PartialEq,
{
    pub fn new() -> Self {
        Self {
            closed: false,
            next_waiter_id: 0,
            workers: Default::default(),
            available: VecDeque::new(),
            waiters: VecDeque::new(),
        }
    }

    /// Register `pid` as a worker and add it to the available queue.
    pub fn insert<R: Runtime<Pid = P, Monitor = M>>(&mut self, rt: &R, pid: P) -> bool {
        if self.closed || self.workers.contains_key(&pid) {
            return false;
        }
        let Some(monitor) = rt.monitor(pid) else {
            return false;
        };
        self.workers.insert(
            pid,
            Worker {
                monitor,
                status: WorkerStatus::Leased,
            },
        );

        self.route(rt, pid);
        true
    }

    /// Take a worker, or register `caller` as a waiter.
    pub fn checkout<R: Runtime<Pid = P, Monitor = M>>(
        &mut self,
        rt: &R,
        caller: P,
        owner: P,
    ) -> Checkout<P> {
        if self.closed {
            return Checkout::Closed;
        }

        if let Some(pid) = self.available.pop_back() {
            // We can unwrap there, as there **must** be worker for PID in available queue
            self.workers
                .get_mut(&pid)
                .unwrap()
                .set_status(WorkerStatus::Leased);

            return Checkout::Worker(pid);
        }

        let monitor = rt.monitor(caller).expect("caller monitor");
        self.next_waiter_id = self.next_waiter_id.wrapping_add(1);
        if self.next_waiter_id == 0 {
            self.next_waiter_id = 1;
        }
        let id = self.next_waiter_id;
        self.waiters.push_back(Waiter {
            id,
            pid: caller,
            monitor,
        });
        rt.send(owner, Message::MorePower);
        Checkout::Wait(id)
    }

    /// Return a worker to the queue.
    pub fn checkin<S: Sender<Pid = P>>(&mut self, sender: &S, pid: P) {
        self.route(sender, pid)
    }

    fn route<S: Sender<Pid = P>>(&mut self, sender: &S, pid: P) {
        if self.closed {
            return;
        }
        let Some(worker) = self.workers.get_mut(&pid) else {
            return;
        };

        if worker.status != WorkerStatus::Leased {
            return;
        }

        if let Some(waiter) = self.waiters.pop_front() {
            sender.send(
                waiter.pid,
                Message::WorkerAvailable {
                    waiter_id: waiter.id,
                    worker: pid,
                },
            );
            worker.status = WorkerStatus::Dispatching(waiter);
        } else {
            worker.status = WorkerStatus::Available(Instant::now());
            self.available.push_back(pid);
        };
    }

    /// Remove up to `size` idle workers that have been idle longer than
    /// `idle_timeout` milliseconds.
    pub fn cleanup(&mut self, size: usize, idle_timeout: u128) -> Vec<P> {
        let State {
            workers,
            available,
            waiters,
            ..
        } = self;

        // If we have any process waiting, then we should not kill process that
        // can be assigned to it soon. So instead skip that many workers.
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

    /// Confirm a dispatching worker for `waiter_id`.
    pub fn accept<R: Runtime<Pid = P, Monitor = M>>(&mut self, rt: &R, waiter_id: u64) -> bool {
        if self.closed {
            return false;
        }

        let Some(worker) = self
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
                rt.demonitor(waiter.monitor);
                true
            }
            other => {
                worker.status = other;
                false
            }
        }
    }

    /// Stop waiting for `waiter_id`.
    pub fn cancel_wait<R: Runtime<Pid = P, Monitor = M>>(&mut self, rt: &R, waiter_id: u64) {
        if self.closed {
            return;
        }

        if let Some(index) = self.waiters.iter().position(|w| w.id == waiter_id) {
            rt.demonitor(self.waiters.remove(index).unwrap().monitor);
            return;
        }

        let reclaimed = self.workers.iter_mut().find_map(|(pid, worker)| {
            if worker.is_waited_by(waiter_id)
                && let WorkerStatus::Dispatching(waiter) = worker.set_status(WorkerStatus::Leased)
            {
                Some((*pid, waiter.monitor))
            } else {
                None
            }
        });

        if let Some((pid, monitor)) = reclaimed {
            rt.demonitor(monitor);
            self.route(rt, pid);
        }
    }

    /// Close the queue, disconnect every waiter and drop every worker.
    pub fn close<R: Runtime<Pid = P, Monitor = M>>(&mut self, rt: &R) {
        if self.closed {
            return;
        }
        self.closed = true;

        let mut drain = BTreeMap::new();

        // Replace the existing map with empty one to avoid ownership issues
        std::mem::swap(&mut drain, &mut self.workers);

        let workers = drain.into_values().flat_map(Worker::into_waiter);
        for waiter in self.waiters.drain(..).chain(workers) {
            rt.demonitor(waiter.monitor);

            rt.send(
                waiter.pid,
                Message::QueueClosed {
                    waiter_id: waiter.id,
                },
            );
        }
    }

    /// Handle a process going down: it was either a worker or a waiter.
    pub fn down<S: Sender<Pid = P>>(&mut self, sender: &S, monitor: M) {
        let mut reclaimed = None;

        let extracted = self
            .workers
            .extract_if(.., |_, w| w.monitor == monitor)
            .next();

        if let Some((pid, worker)) = extracted {
            self.available.retain(|p| p != &pid);
            if let WorkerStatus::Dispatching(waiter) = worker.status {
                self.waiters.push_front(waiter);
                reclaimed = Some(pid);
            }
        } else if let Some(index) = self.waiters.iter().position(|w| w.monitor == monitor) {
            self.waiters.remove(index);
        } else if let Some((pid, worker)) = self
            .workers
            .iter_mut()
            .find(|(_, w)| w.is_monitored_by(monitor))
            && let WorkerStatus::Dispatching(_waiter) = worker.set_status(WorkerStatus::Leased)
        {
            reclaimed = Some(*pid);
        }

        if let Some(worker_pid) = reclaimed {
            self.route(sender, worker_pid)
        }
    }

    pub fn to_list(&self) -> Vec<P> {
        self.workers.keys().copied().collect()
    }

    pub fn size(&self) -> usize {
        self.workers.len()
    }

    pub fn stats(&self, owner: P) -> (P, usize, usize, usize) {
        (
            owner,
            self.available.len(),
            self.workers.len(),
            self.waiters.len(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;
    use std::time::{Duration, Instant};

    const OWNER: Pid = 999;

    type Pid = u64;

    #[derive(Default)]
    struct FakeRuntime {
        next_monitor: RefCell<u64>,
        monitors: RefCell<HashMap<Pid, u64>>,
        demonitored: RefCell<Vec<u64>>,
        sent: RefCell<Vec<(Pid, Message<Pid>)>>,
        monitor_fails: RefCell<bool>,
    }

    impl FakeRuntime {
        fn new() -> Self {
            Self::default()
        }

        fn monitor_for(&self, pid: Pid) -> u64 {
            *self.monitors.borrow().get(&pid).expect("pid is monitored")
        }

        fn sent(&self) -> Vec<(Pid, Message<Pid>)> {
            self.sent.borrow().clone()
        }

        fn take_sent(&self) -> Vec<(Pid, Message<Pid>)> {
            self.sent.borrow_mut().drain(..).collect()
        }

        fn demonitored(&self) -> Vec<u64> {
            self.demonitored.borrow().clone()
        }
    }

    impl Sender for FakeRuntime {
        type Pid = Pid;

        fn send(&self, pid: Pid, message: Message<Pid>) {
            self.sent.borrow_mut().push((pid, message));
        }
    }

    impl Runtime for FakeRuntime {
        type Monitor = u64;

        fn monitor(&self, pid: Pid) -> Option<u64> {
            if *self.monitor_fails.borrow() {
                return None;
            }

            let mut next = self.next_monitor.borrow_mut();
            *next += 1;
            self.monitors.borrow_mut().insert(pid, *next);
            Some(*next)
        }

        fn demonitor(&self, monitor: u64) {
            self.demonitored.borrow_mut().push(monitor);
        }
    }

    fn state() -> State<Pid, u64> {
        State::new()
    }

    fn mark_idle_since(state: &mut State<Pid, u64>, pid: Pid, idle_for: Duration) {
        state.workers.get_mut(&pid).unwrap().status =
            WorkerStatus::Available(Instant::now() - idle_for);
    }

    #[test]
    fn insert_registers_worker_as_available() {
        let rt = FakeRuntime::new();
        let mut state = state();

        assert!(state.insert(&rt, 1));
        assert_eq!(state.size(), 1);
        assert_eq!(state.to_list(), vec![1]);
        assert_eq!(state.stats(OWNER), (OWNER, 1, 1, 0));
        assert!(rt.sent().is_empty());
    }

    #[test]
    fn insert_rejects_duplicate_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();

        assert!(state.insert(&rt, 1));
        assert!(!state.insert(&rt, 1));
        assert_eq!(state.size(), 1);
    }

    #[test]
    fn insert_rejects_worker_when_closed() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.closed = true;

        assert!(!state.insert(&rt, 1));
        assert_eq!(state.size(), 0);
    }

    #[test]
    fn insert_fails_when_monitor_fails() {
        let rt = FakeRuntime::new();
        *rt.monitor_fails.borrow_mut() = true;
        let mut state = state();

        assert!(!state.insert(&rt, 1));
        assert_eq!(state.size(), 0);
    }

    #[test]
    fn checkout_hands_out_available_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);

        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Worker(1));
        assert_eq!(state.stats(OWNER), (OWNER, 0, 1, 0));
        assert!(rt.sent().is_empty());
    }

    #[test]
    fn checkout_without_worker_registers_waiter() {
        let rt = FakeRuntime::new();
        let mut state = state();

        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        assert_eq!(state.stats(OWNER), (OWNER, 0, 0, 1));
        assert_eq!(rt.sent(), vec![(OWNER, Message::MorePower)]);
    }

    #[test]
    fn checkout_on_closed_queue_returns_closed() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.closed = true;

        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Closed);
        assert!(rt.sent().is_empty());
    }

    #[test]
    fn waiter_ids_are_monotonic_and_skip_zero() {
        let rt = FakeRuntime::new();
        let mut state = state();

        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        assert_eq!(state.checkout(&rt, 3, OWNER), Checkout::Wait(2));

        state.next_waiter_id = u64::MAX;
        assert_eq!(state.checkout(&rt, 4, OWNER), Checkout::Wait(1));
    }

    #[test]
    fn insert_dispatches_worker_to_waiting_waiter() {
        let rt = FakeRuntime::new();
        let mut state = state();

        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        rt.take_sent();
        assert!(state.insert(&rt, 1));

        assert_eq!(
            rt.sent(),
            vec![(
                2,
                Message::WorkerAvailable {
                    waiter_id: 1,
                    worker: 1,
                }
            )]
        );
        assert_eq!(state.stats(OWNER), (OWNER, 0, 1, 0));
        assert!(matches!(
            &state.workers[&1].status,
            WorkerStatus::Dispatching(_)
        ));
    }

    #[test]
    fn checkin_returns_worker_to_available_pool() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Worker(1));

        state.checkin(&rt, 1);

        assert_eq!(state.stats(OWNER), (OWNER, 1, 1, 0));
        assert!(matches!(
            &state.workers[&1].status,
            WorkerStatus::Available(_)
        ));
    }

    #[test]
    fn checkin_of_leased_worker_is_ignored() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);

        // Worker is still leased after insert? No: insert marks it available.
        // Leasing happens on checkout, so check in the worker twice.
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Worker(1));
        state.checkin(&rt, 1);
        state.checkin(&rt, 1);

        assert_eq!(state.stats(OWNER), (OWNER, 1, 1, 0));
    }

    #[test]
    fn accept_confirms_dispatching_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);
        let waiter_monitor = rt.monitor_for(2);

        assert!(state.accept(&rt, 1));
        assert_eq!(rt.demonitored(), vec![waiter_monitor]);
        assert_eq!(state.stats(OWNER), (OWNER, 0, 1, 0));
    }

    #[test]
    fn accept_unknown_waiter_keeps_dispatching_state() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);

        assert!(!state.accept(&rt, 99));
        assert!(rt.demonitored().is_empty());
        assert!(matches!(
            &state.workers[&1].status,
            WorkerStatus::Dispatching(_)
        ));
    }

    #[test]
    fn accept_on_closed_queue_returns_false() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.closed = true;

        assert!(!state.accept(&rt, 1));
    }

    #[test]
    fn cancel_wait_removes_queued_waiter() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        assert_eq!(state.checkout(&rt, 3, OWNER), Checkout::Wait(2));

        state.cancel_wait(&rt, 1);

        assert_eq!(rt.demonitored(), vec![rt.monitor_for(2)]);
        assert_eq!(state.stats(OWNER), (OWNER, 0, 0, 1));
    }

    #[test]
    fn cancel_wait_reclaims_dispatching_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);
        rt.take_sent();

        state.cancel_wait(&rt, 1);

        assert_eq!(rt.demonitored(), vec![rt.monitor_for(2)]);
        assert_eq!(state.stats(OWNER), (OWNER, 1, 1, 0));
        assert!(rt.sent().is_empty());
    }

    #[test]
    fn cancel_wait_unknown_id_is_noop() {
        let rt = FakeRuntime::new();
        let mut state = state();

        state.cancel_wait(&rt, 42);

        assert!(rt.demonitored().is_empty());
        assert_eq!(state.stats(OWNER), (OWNER, 0, 0, 0));
    }

    #[test]
    fn cleanup_removes_idle_workers_beyond_size() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);
        state.insert(&rt, 2);
        state.insert(&rt, 3);

        for pid in [1, 2, 3] {
            mark_idle_since(&mut state, pid, Duration::from_secs(60));
        }

        let removed = state.cleanup(2, 1_000);

        assert_eq!(removed, vec![1, 2]);
        assert_eq!(state.to_list(), vec![3]);
    }

    #[test]
    fn cleanup_keeps_recently_idle_workers() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);

        let removed = state.cleanup(10, 60_000);

        assert!(removed.is_empty());
        assert_eq!(state.size(), 1);
    }

    #[test]
    fn cleanup_reserves_workers_for_waiters() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);
        mark_idle_since(&mut state, 1, Duration::from_secs(60));

        // A pending waiter reduces the number of workers eligible for cleanup.
        state.waiters.push_back(Waiter {
            id: 1,
            pid: 10,
            monitor: 100,
        });

        // The single pending waiter consumes the whole cleanup budget, so the
        // idle worker is kept even though it is past its idle timeout.
        let removed = state.cleanup(1, 0);

        assert!(removed.is_empty());
        assert_eq!(state.size(), 1);
    }

    #[test]
    fn close_notifies_waiters_and_drops_workers() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Worker(1));
        assert_eq!(state.checkout(&rt, 3, OWNER), Checkout::Wait(1));
        rt.take_sent();

        state.close(&rt);

        assert!(state.closed);
        assert_eq!(state.size(), 0);
        assert!(state.to_list().is_empty());
        assert_eq!(rt.sent(), vec![(3, Message::QueueClosed { waiter_id: 1 })]);
    }

    #[test]
    fn close_notifies_dispatching_workers() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);
        rt.take_sent();

        state.close(&rt);

        assert_eq!(rt.sent(), vec![(2, Message::QueueClosed { waiter_id: 1 })]);
    }

    #[test]
    fn close_is_idempotent() {
        let rt = FakeRuntime::new();
        let mut state = state();

        state.close(&rt);
        let first = rt.sent();
        state.close(&rt);

        assert_eq!(rt.sent(), first);
    }

    #[test]
    fn down_removes_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);
        let monitor = rt.monitor_for(1);

        state.down(&rt, monitor);

        assert_eq!(state.size(), 0);
        assert_eq!(state.available.len(), 0);
    }

    #[test]
    fn down_on_dispatching_worker_requeues_waiter() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);
        let worker_monitor = rt.monitor_for(1);

        state.down(&rt, worker_monitor);

        assert_eq!(state.size(), 0);
        assert_eq!(state.waiters.len(), 1);
        assert_eq!(state.waiters[0].id, 1);
    }

    #[test]
    fn down_on_waiter_reclaims_worker() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        state.insert(&rt, 1);
        let waiter_monitor = rt.monitor_for(2);

        state.down(&rt, waiter_monitor);

        assert_eq!(state.stats(OWNER), (OWNER, 1, 1, 0));
        assert!(state.waiters.is_empty());
    }

    #[test]
    fn down_removes_queued_waiter() {
        let rt = FakeRuntime::new();
        let mut state = state();
        assert_eq!(state.checkout(&rt, 2, OWNER), Checkout::Wait(1));
        let waiter_monitor = rt.monitor_for(2);

        state.down(&rt, waiter_monitor);

        assert!(state.waiters.is_empty());
    }

    #[test]
    fn down_with_unknown_monitor_is_noop() {
        let rt = FakeRuntime::new();
        let mut state = state();
        state.insert(&rt, 1);

        state.down(&rt, 4_242);

        assert_eq!(state.size(), 1);
        assert_eq!(state.available.len(), 1);
    }
}
