// SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

// Integration tests for the `pg` client (node-postgres) through Ultravisor.
//
// Only tests that observe server or proxy behaviour are here. Client-side
// features (option parsing, query building, result shaping, error object
// fields) are not tested: the `pg` package has its own suite for those.
//
// The environment provides the connection settings, as it does for the
// postgres.js suite: PGHOST, PGPORT, PGUSER, PGPASS, PGDATABASE, and PGMODE.
// `PGUSER` carries the tenant name, so the tests never replace it.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Readable } from 'node:stream'

import pg from 'pg'
import copyStreams from 'pg-copy-streams'

const { from: copyFrom, to: copyTo } = copyStreams

const TRANSACTION_MODE = process.env.PGMODE === 'transaction'

const settings = () => ({
  host: process.env.PGHOST,
  port: Number(process.env.PGPORT),
  user: process.env.PGUSER,
  password: process.env.PGPASS,
  database: process.env.PGDATABASE
})

const connect = async (overrides = {}) => {
  const client = new pg.Client({ ...settings(), ...overrides })
  await client.connect()
  return client
}

const drop = async (client, table) => {
  await client.query(`drop table if exists ${table}`)
}

// Closes the client even when the cleanup fails, so that no socket stays open
// and the runner does not wait for it after a test. A failed transaction
// rejects every later query with 25P02, and a broken connection rejects
// everything.
const close = async (client, table) => {
  if (table) {
    await client.query('rollback').catch(() => {})
    await client.query(`drop table if exists ${table}`).catch(() => {})
  }

  await client.end().catch(() => {})
}

test('connects and runs a text query', async () => {
  const client = await connect()
  try {
    const result = await client.query('select 1 as n')

    assert.deepStrictEqual(result.rows, [{ n: 1 }])
    assert.strictEqual(result.rowCount, 1)
    assert.strictEqual(result.command, 'SELECT')
  } finally {
    await close(client)
  }
})

test('runs several statements in one text query', async () => {
  const client = await connect()
  try {
    const results = await client.query('select 1 as a; select 2 as b')

    assert.deepStrictEqual(
      results.map(result => result.rows),
      [[{ a: 1 }], [{ b: 2 }]]
    )
  } finally {
    await close(client)
  }
})

test('runs a text query in the extended protocol', async () => {
  const client = await connect()
  try {
    const result = await client.query({ text: 'select 42 as n', queryMode: 'extended' })

    assert.deepStrictEqual(result.rows, [{ n: 42 }])
  } finally {
    await close(client)
  }
})

test('binds parameters of several types', async () => {
  const client = await connect()
  try {
    const result = await client.query(
      `select $1::text as text_value, $2::integer as int_value, $3::boolean as bool_value,
              $4::bytea as binary_value, $5::jsonb as json_value, $6::integer[] as array_value,
              $7::text as null_value`,
      ['text', 7, true, Buffer.from([1, 2, 3]), { a: 1 }, [1, 2, 3], null]
    )

    assert.deepStrictEqual(result.rows, [
      {
        text_value: 'text',
        int_value: 7,
        bool_value: true,
        binary_value: Buffer.from([1, 2, 3]),
        json_value: { a: 1 },
        array_value: [1, 2, 3],
        null_value: null
      }
    ])
  } finally {
    await close(client)
  }
})

test('reuses a named prepared statement', async () => {
  const client = await connect()
  try {
    const statement = { name: 'ultravisor_pg_statement', text: 'select $1::integer as n' }

    // The second call sends Bind, Describe, and Execute only, so the proxy
    // must hold the statement for the client.
    const first = await client.query({ ...statement, values: [1] })
    const second = await client.query({ ...statement, values: [2] })

    assert.strictEqual(first.rows[0].n, 1)
    assert.strictEqual(second.rows[0].n, 2)
  } finally {
    await close(client)
  }
})

test('splits a result into portal batches', async () => {
  const client = await connect()
  try {
    // The client asks for two rows per Execute, so the server suspends the
    // portal after each batch.
    const result = await client.query({ text: 'select generate_series(1, 5) as n', rows: 2 })

    assert.deepStrictEqual(
      result.rows.map(row => row.n),
      [1, 2, 3, 4, 5]
    )
  } finally {
    await close(client)
  }
})

test('commits a transaction', async () => {
  const table = 'ultravisor_pg_commit'
  const client = await connect()
  try {
    await drop(client, table)
    await client.query(`create table ${table} (n integer)`)

    await client.query('begin')
    await client.query(`insert into ${table} values (1)`)
    await client.query('commit')

    const { rows } = await client.query(`select count(*)::integer as c from ${table}`)
    assert.strictEqual(rows[0].c, 1)
  } finally {
    await close(client, table)
  }
})

test('rolls back a transaction', async () => {
  const table = 'ultravisor_pg_rollback'
  const client = await connect()
  try {
    await drop(client, table)
    await client.query(`create table ${table} (n integer)`)

    await client.query('begin')
    await client.query(`insert into ${table} values (1)`)
    await client.query('rollback')

    const { rows } = await client.query(`select count(*)::integer as c from ${table}`)
    assert.strictEqual(rows[0].c, 0)
  } finally {
    await close(client, table)
  }
})

test('recovers after an error inside a transaction', async () => {
  const client = await connect()
  try {
    await client.query('begin')

    const error = await client.query('select from').catch(error => error)
    assert.strictEqual(error.code, '42601')

    await client.query('rollback')

    const { rows } = await client.query('select 1 as n')
    assert.strictEqual(rows[0].n, 1)
  } finally {
    await close(client)
  }
})

test('keeps the transactions of two clients apart', async () => {
  const table = 'ultravisor_pg_isolation'
  const setup = await connect()

  try {
    await drop(setup, table)
    await setup.query(`create table ${table} (n integer)`)
  } finally {
    await close(setup)
  }

  const [first, second] = await Promise.all([connect(), connect()])
  try {
    await Promise.all([first.query('begin'), second.query('begin')])
    await Promise.all([
      first.query(`insert into ${table} values (1)`),
      second.query(`insert into ${table} values (2)`)
    ])

    const [firstRows, secondRows] = await Promise.all([
      first.query(`select count(*)::integer as c from ${table}`),
      second.query(`select count(*)::integer as c from ${table}`)
    ])

    // An open transaction must see its own row only. The proxy must not share
    // one backend between the two transactions.
    assert.strictEqual(firstRows.rows[0].c, 1)
    assert.strictEqual(secondRows.rows[0].c, 1)

    await Promise.all([first.query('commit'), second.query('commit')])

    const { rows } = await first.query(`select count(*)::integer as c from ${table}`)
    assert.strictEqual(rows[0].c, 2)
  } finally {
    await Promise.all([close(first, table), close(second)])
  }
})

test('serves queries from a pool', async () => {
  const pool = new pg.Pool({ ...settings(), max: 2 })
  try {
    const [first, second] = await Promise.all([
      pool.query('select 1 as n'),
      pool.query('select 2 as n')
    ])

    assert.strictEqual(first.rows[0].n, 1)
    assert.strictEqual(second.rows[0].n, 2)
  } finally {
    await pool.end().catch(() => {})
  }
})

test('works after the client closes and connects again', async () => {
  const first = await connect()
  let firstRows

  try {
    firstRows = await first.query('select 1 as n')
  } finally {
    await close(first)
  }

  const second = await connect()
  try {
    const secondRows = await second.query('select 2 as n')

    assert.strictEqual(firstRows.rows[0].n, 1)
    assert.strictEqual(secondRows.rows[0].n, 2)
  } finally {
    await close(second)
  }
})

test('refuses a connection for an unknown tenant', async () => {
  const client = new pg.Client({ ...settings(), user: `${process.env.PGUSER}_missing` })

  // A connection that fails before the handshake emits `error`.
  client.on('error', () => {})

  await assert.rejects(client.connect(), 'an unknown tenant must be refused')
})

test('reports a server error', async () => {
  const client = await connect()
  try {
    const error = await client.query('select from').catch(error => error)

    assert.strictEqual(error.code, '42601')
  } finally {
    await close(client)
  }
})

test('reports a constraint violation', async () => {
  const table = 'ultravisor_pg_constraint'
  const client = await connect()
  try {
    await drop(client, table)
    await client.query(`create table ${table} (n integer primary key)`)
    await client.query(`insert into ${table} values (1)`)

    const error = await client.query(`insert into ${table} values (1)`).catch(error => error)
    assert.strictEqual(error.code, '23505')
  } finally {
    await close(client, table)
  }
})

test('forwards server notices', async () => {
  const client = await connect()
  try {
    const notices = []
    client.on('notice', message => notices.push(message))

    await client.query('drop table if exists ultravisor_pg_missing_table')

    assert.strictEqual(notices.length, 1)
    assert.strictEqual(notices[0].severity, 'NOTICE')
    assert.match(notices[0].message, /does not exist/)
  } finally {
    await close(client)
  }
})

test('round-trips column values of several types', async () => {
  const client = await connect()
  try {
    const result = await client.query(
      `select 1::smallint as int2_value,
              2::integer as int4_value,
              3::bigint as int8_value,
              4.5::numeric as numeric_value,
              5.5::double precision as float_value,
              'text'::text as text_value,
              true::boolean as bool_value,
              decode('010203', 'hex') as binary_value,
              '{"a": 1}'::jsonb as json_value,
              '2024-01-02T03:04:05Z'::timestamptz as timestamp_value,
              array[1, 2, 3] as array_value`
    )

    assert.deepStrictEqual(result.rows, [
      {
        int2_value: 1,
        int4_value: 2,
        // The client keeps 64-bit integers and decimals as strings.
        int8_value: '3',
        numeric_value: '4.5',
        float_value: 5.5,
        text_value: 'text',
        bool_value: true,
        binary_value: Buffer.from([1, 2, 3]),
        json_value: { a: 1 },
        timestamp_value: new Date('2024-01-02T03:04:05.000Z'),
        array_value: [1, 2, 3]
      }
    ])
  } finally {
    await close(client)
  }
})

test('retrieves a large value', async () => {
  const client = await connect()
  try {
    const { rows } = await client.query(`select repeat('x', 200000) as value`)

    assert.strictEqual(rows[0].value.length, 200000)
  } finally {
    await close(client)
  }
})

test('retrieves many rows', async () => {
  const client = await connect()
  try {
    const result = await client.query('select generate_series(1, 10000) as n')

    assert.strictEqual(result.rowCount, 10000)
    assert.strictEqual(result.rows[0].n, 1)
    assert.strictEqual(result.rows.at(-1).n, 10000)
  } finally {
    await close(client)
  }
})

test('copies rows out of the server', async () => {
  const table = 'ultravisor_pg_copy_out'
  const client = await connect()
  try {
    await drop(client, table)
    await client.query(`create table ${table} (n integer)`)
    await client.query(`insert into ${table} values (1), (2), (3)`)

    const chunks = []
    for await (const chunk of client.query(copyTo(`copy ${table} to stdout`))) {
      chunks.push(chunk)
    }

    assert.strictEqual(Buffer.concat(chunks).toString(), '1\n2\n3\n')
  } finally {
    await close(client, table)
  }
})

test('copies rows into the server', async () => {
  const table = 'ultravisor_pg_copy_in'
  const client = await connect()
  try {
    await drop(client, table)
    await client.query(`create table ${table} (n integer)`)

    const stream = client.query(copyFrom(`copy ${table} from stdin`))
    const finished = new Promise((resolve, reject) => {
      stream.on('finish', resolve)
      stream.on('error', reject)
    })

    Readable.from(['1\n', '2\n', '3\n']).pipe(stream)
    await finished

    const { rows } = await client.query(`select sum(n)::integer as total from ${table}`)
    assert.strictEqual(rows[0].total, 6)
  } finally {
    await close(client, table)
  }
})

// Transaction mode gives every transaction a backend of its own, so a LISTEN
// subscription cannot survive between two statements.
if (!TRANSACTION_MODE) {
  test('delivers LISTEN/NOTIFY notifications', async () => {
    const listener = await connect()
    const notifier = await connect()
    try {
      await listener.query('listen ultravisor_pg_channel')

      const received = new Promise(resolve => listener.once('notification', resolve))
      await notifier.query(`notify ultravisor_pg_channel, 'payload'`)

      const notification = await received
      assert.strictEqual(notification.channel, 'ultravisor_pg_channel')
      assert.strictEqual(notification.payload, 'payload')
    } finally {
      await Promise.all([close(listener), close(notifier)])
    }
  })
}
