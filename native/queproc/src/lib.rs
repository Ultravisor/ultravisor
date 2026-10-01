// SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

mod core;

use parking_lot::Mutex;
use rustler::{Env, LocalPid};

use core::{Checkout, Message, Runtime, Sender, State};

rustler::atoms! {
    worker,
    wait,
    closed,
    worker_available,
    queue_closed,
    more_power,
}

type CoreState = State<LocalPid, rustler::Monitor>;

struct Queproc {
    owner: LocalPid,
    state: Mutex<CoreState>,
}

impl std::panic::RefUnwindSafe for Queproc {}

/// Sends queue messages to BEAM processes.
struct NifSender<'a> {
    env: Env<'a>,
}

impl Sender for NifSender<'_> {
    type Pid = LocalPid;

    fn send(&self, pid: LocalPid, message: Message<LocalPid>) {
        let _ = match message {
            Message::MorePower => self.env.send(&pid, more_power()),
            Message::WorkerAvailable { waiter_id, worker } => {
                self.env.send(&pid, (worker_available(), waiter_id, worker))
            }
            Message::QueueClosed { waiter_id } => self.env.send(&pid, (queue_closed(), waiter_id)),
        };
    }
}

/// [`Sender`] plus monitor management backed by the owning resource.
struct NifRuntime<'a, 'r> {
    sender: NifSender<'a>,
    resource: &'r rustler::ResourceArc<Queproc>,
}

impl Sender for NifRuntime<'_, '_> {
    type Pid = LocalPid;

    fn send(&self, pid: LocalPid, message: Message<LocalPid>) {
        self.sender.send(pid, message);
    }
}

impl Runtime for NifRuntime<'_, '_> {
    type Monitor = rustler::Monitor;

    fn monitor(&self, pid: LocalPid) -> Option<rustler::Monitor> {
        self.resource.monitor(Some(self.sender.env), &pid)
    }

    fn demonitor(&self, monitor: rustler::Monitor) {
        self.resource.demonitor(Some(self.sender.env), &monitor);
    }
}

#[rustler::resource_impl]
impl rustler::Resource for Queproc {
    fn down(&self, env: Env, _pid: LocalPid, monitor: rustler::Monitor) {
        let sender = NifSender { env };
        self.state.lock().down(&sender, monitor);
    }
}

#[rustler::nif]
fn new<'a>(env: Env<'a>) -> rustler::ResourceArc<Queproc> {
    rustler::ResourceArc::new(Queproc {
        owner: env.pid(),
        state: Mutex::new(State::new()),
    })
}

#[rustler::nif]
fn insert(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) -> bool {
    let rt = NifRuntime {
        sender: NifSender { env },
        resource: &queue,
    };

    queue.state.lock().insert(&rt, pid)
}

#[rustler::nif]
fn checkout<'a>(
    env: Env<'a>,
    queue: rustler::ResourceArc<Queproc>,
) -> (rustler::Atom, Option<LocalPid>, u64) {
    let rt = NifRuntime {
        sender: NifSender { env },
        resource: &queue,
    };
    let owner = queue.owner;

    match queue.state.lock().checkout(&rt, env.pid(), owner) {
        Checkout::Closed => (closed(), None, 0),
        Checkout::Worker(pid) => (worker(), Some(pid), 0),
        Checkout::Wait(id) => (wait(), None, id),
    }
}

#[rustler::nif]
fn checkin(env: Env, queue: rustler::ResourceArc<Queproc>, pid: LocalPid) {
    let sender = NifSender { env };
    queue.state.lock().checkin(&sender, pid)
}

#[rustler::nif]
fn cleanup(queue: rustler::ResourceArc<Queproc>, size: usize, idle_timeout: u128) -> Vec<LocalPid> {
    queue.state.lock().cleanup(size, idle_timeout)
}

#[rustler::nif]
fn accept(env: Env, queue: rustler::ResourceArc<Queproc>, waiter_id: u64) -> bool {
    let rt = NifRuntime {
        sender: NifSender { env },
        resource: &queue,
    };

    queue.state.lock().accept(&rt, waiter_id)
}

#[rustler::nif]
fn cancel_wait(env: Env, queue: rustler::ResourceArc<Queproc>, waiter_id: u64) {
    let rt = NifRuntime {
        sender: NifSender { env },
        resource: &queue,
    };

    queue.state.lock().cancel_wait(&rt, waiter_id)
}

#[rustler::nif]
fn close(env: Env, queue: rustler::ResourceArc<Queproc>) {
    let rt = NifRuntime {
        sender: NifSender { env },
        resource: &queue,
    };

    queue.state.lock().close(&rt)
}

#[rustler::nif]
fn to_list(queue: &Queproc) -> Vec<LocalPid> {
    queue.state.lock().to_list()
}

#[rustler::nif]
fn size(queue: &Queproc) -> usize {
    queue.state.lock().size()
}

#[rustler::nif]
fn stats(queue: &Queproc) -> (LocalPid, usize, usize, usize) {
    let owner = queue.owner;
    queue.state.lock().stats(owner)
}

rustler::init!("Elixir.Queproc.Native");
