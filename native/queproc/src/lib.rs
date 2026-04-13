// SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

use std::collections::VecDeque;
use std::sync::RwLock;

use rustler::{Env, LocalPid};

rustler::atoms! {
    worker_died,
    worker_available,

    more_power,
}

struct Queproc {
    owner: LocalPid,
    workers: RwLock<VecDeque<LocalPid>>,
    monitors: RwLock<Vec<(LocalPid, rustler::Monitor)>>,
    waiters: RwLock<VecDeque<(LocalPid, rustler::Monitor)>>,
}

unsafe impl Send for Queproc {}
unsafe impl Sync for Queproc {}

#[rustler::resource_impl]
impl rustler::Resource for Queproc {
    fn down(&self, _env: Env, _pid: LocalPid, monitor: rustler::Monitor) {
        let mut w = self.workers.write().unwrap();
        let mut m = self.monitors.write().unwrap();
        let mut wait = self.waiters.write().unwrap();

        m.retain(|(pid, mon)| {
            if mon == &monitor {
                w.retain(|p| p != pid);
                false
            } else {
                true
            }
        });

        wait.retain(|(_, mon)| mon != &monitor);

        // let _ = env.send(&self.manager, (worker_died(), pid));
    }
}

#[rustler::nif]
fn new<'a>(env: Env<'a>) -> rustler::ResourceArc<Queproc> {
    rustler::ResourceArc::new(Queproc {
        owner: env.pid(),
        workers: Default::default(),
        monitors: Default::default(),
        waiters: Default::default(),
    })
}

#[rustler::nif]
fn insert(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) -> LocalPid {
    let mut m = queue.monitors.write().unwrap();
    let monitor = queue.monitor(Some(env), &pid).unwrap();

    m.push((pid, monitor));

    do_checkin(env, &queue, pid);

    pid
}

#[rustler::nif]
fn checkout<'a>(
    env: Env<'a>,
    queue: rustler::ResourceArc<Queproc>,
) -> Option<LocalPid> {
    let mut q = queue.workers.write().unwrap();

    match q.pop_back() {
        Some(pid) => {
            Some(pid)
        }
        None => {
            // TODO: Send that message, when more power is needed
            // let _ = env.send(&queue.owner, more_power());
            let monitor = queue.monitor(Some(env), &env.pid()).unwrap();
            let mut w = queue.waiters.write().unwrap();
            w.push_back((env.pid(), monitor));
            None
        }
    }
}

#[rustler::nif]
fn checkin(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) {
    do_checkin(env, &queue, pid)
}

fn do_checkin(env: Env, queue: &rustler::ResourceArc<Queproc>, pid: LocalPid) {
    let mut q = queue.workers.write().unwrap();
    let mut w = queue.waiters.write().unwrap();

    loop {
        match w.pop_front() {
            None => {
                q.push_back(pid);
                return;
            }
            Some((wpid, mon)) => match env.send(&wpid, (worker_available(), pid)) {
                Ok(_) => {
                    queue.demonitor(Some(env), &mon);
                    return;
                }
                Err(_) => (),
            },
        }
    }
}

#[rustler::nif]
fn cancel_wait(env: Env, queue: rustler::ResourceArc<Queproc>) {
    let mut w = queue.waiters.write().unwrap();
    let pid = env.pid();

    w.retain(|(p, mon)| {
        if p == &pid {
            queue.demonitor(Some(env), mon);
            false
        } else {
            true
        }
    });
}

#[rustler::nif]
fn drop(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) {
    let mut q = queue.workers.write().unwrap();
    let mut m = queue.monitors.write().unwrap();

    m.retain(|(p, mon)| {
        if p != &pid {
            queue.demonitor(Some(env), mon);
            true
        } else {
            false
        }
    });
    q.retain(|p| p != &pid);
}

#[rustler::nif]
fn to_list<'a>(queue: &Queproc) -> Vec<LocalPid> {
    let q = queue.workers.read().unwrap();

    q.iter()
        .map(|pid| pid.clone())
        .collect()
}

#[rustler::nif]
fn size(queue: &Queproc) -> usize {
    queue.workers.read().unwrap().len()
}

#[rustler::nif]
fn stats(queue: &Queproc) -> (LocalPid, usize, usize, usize) {
    (
        queue.owner,
        queue.workers.read().unwrap().len(),
        queue.monitors.read().unwrap().len(),
        queue.waiters.read().unwrap().len(),
    )
}

rustler::init!("Elixir.Queproc.Native");
