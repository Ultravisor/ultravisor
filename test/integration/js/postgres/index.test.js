// SPDX-FileCopyrightText: 2025-2026 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: EUPL-1.2

import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import net from 'node:net'
import fs from 'node:fs'
import crypto from 'node:crypto'

import postgres from 'postgres'

const delay = ms => new Promise(r => setTimeout(r, ms))

const rel = x => new URL(x, import.meta.url)

// Timeout for one test, in milliseconds. The TIMEOUT environment variable
// holds the value in seconds.
const TEST_TIMEOUT = Number(process.env.TIMEOUT ?? 5) * 1000
// Timeout for the client options, in seconds.
const CLIENT_TIMEOUT = Number(process.env.TIMEOUT ?? 5)

const login = {
  user: process.env.PGUSER,
  pass: process.env.PGPASS,
}

const options = {
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  db: process.env.PGDATABASE,
  ssl: (process.env.PGSSL ? { rejectUnauthorized: false } : false),
  prepare: true,
  user: login.user,
  pass: login.pass,
  idle_timeout: CLIENT_TIMEOUT,
  connect_timeout: CLIENT_TIMEOUT,
  max: 1
}

const sql = postgres(options)

await sql`DROP SCHEMA IF EXISTS test CASCADE`
await sql`CREATE SCHEMA test`

after(async () => { await sql.end() })

//t('Connects with no options', async() => {
//  const sql = postgres({ max: 1 })
//
//  const result = (await sql`select 1 as x`)[0].x
//  await sql.end()
//
//  return [1, result]
//})

//t('Uses default database without slash', async() => {
//  const sql = postgres('postgres://localhost')
//  return [sql.options.user, sql.options.database]
//})
//
//t('Uses default database with slash', async() => {
//  const sql = postgres('postgres://localhost/')
//  return [sql.options.user, sql.options.database]
//})

test('Result is array', async () => { assert.strictEqual(Array.isArray(await sql`select 1`), true) })

test('Result has count', async () => { assert.strictEqual((await sql`select 1`).count, 1) })

test('Result has command', async () => { assert.strictEqual((await sql`select 1`).command, 'SELECT') })

test('Create table', async () => {
  const created = await sql`create table test.test(int int)`
  await sql`drop table test.test`
  assert.strictEqual(created.command, 'CREATE TABLE')
})

test('Drop table', { timeout: TEST_TIMEOUT * 2 }, async () => {
  await sql`create table test.test(int int)`
  assert.strictEqual((await sql`drop table test.test`).command, 'DROP TABLE')
})

test('null', async () => { assert.strictEqual((await sql`select ${ null } as x`)[0].x, null) })

test('Integer', async () => { assert.strictEqual((await sql`select ${ 1 } as x`)[0].x, '1') })

test('String', async () => { assert.strictEqual((await sql`select ${ 'hello' } as x`)[0].x, 'hello') })

test('Boolean false', async () => { assert.strictEqual((await sql`select ${ false } as x`)[0].x, false) })

test('Boolean true', async () => { assert.strictEqual((await sql`select ${ true } as x`)[0].x, true) })

test('Date', async () => {
  const now = new Date()
  assert.strictEqual(0, now - (await sql`select ${ now } as x`)[0].x)
})

test('Json', async () => {
  const x = (await sql`select ${ sql.json({ a: 'hello', b: 42 }) } as x`)[0].x
  assert.strictEqual([x.a, x.b].join(), 'hello,42')
})

test('implicit json', async () => {
  const x = (await sql`select ${ { a: 'hello', b: 42 } }::json as x`)[0].x
  assert.strictEqual([x.a, x.b].join(), 'hello,42')
})

test('implicit jsonb', async () => {
  const x = (await sql`select ${ { a: 'hello', b: 42 } }::jsonb as x`)[0].x
  assert.strictEqual([x.a, x.b].join(), 'hello,42')
})

test('Empty array', async () => { assert.strictEqual(Array.isArray((await sql`select ${ sql.array([], 1009) } as x`)[0].x), true) })

test('String array', async () => { assert.strictEqual((await sql`select ${ '{1,2,3}' }::int[] as x`)[0].x.join(''), '123') })

test('Array of Integer', async () => { assert.strictEqual((await sql`select ${ sql.array([1, 2, 3]) } as x`)[0].x[2], '3') })

test('Array of String', async () => { assert.strictEqual((await sql`select ${ sql.array(['a', 'b', 'c']) } as x`)[0].x[2], 'c') })

test('Array of Date', async () => {
  const now = new Date()
  assert.strictEqual((await sql`select ${ sql.array([now, now, now]) } as x`)[0].x[2].getTime(), now.getTime())
})

test('Array of Box', async () => {
  assert.strictEqual((await sql`select ${ '{(1,2),(3,4);(4,5),(6,7)}' }::box[] as x`)[0].x.join(';'), '(3,4),(1,2);(6,7),(4,5)')
})

test('Nested array n2', async () => { assert.strictEqual((await sql`select ${ sql.array([[1, 2], [3, 4]]) } as x`)[0].x[1][1], '4') })

test('Nested array n3', async () => { assert.strictEqual((await sql`select ${ sql.array([[[1, 2]], [[3, 4]], [[5, 6]]]) } as x`)[0].x[2][0][1], '6') })

test('Escape in arrays', async () => { assert.strictEqual((await sql`select ${ sql.array(['Hello "you"', 'c:\\windows']) } as x`)[0].x.join(','), 'Hello "you",c:\\windows') })

test('Escapes', async () => {
  assert.strictEqual(Object.keys((await sql`select 1 as ${ sql('hej"hej') }`)[0])[0], 'hej"hej')
})

test('null for int', async () => {
  await sql`create table test.test (x int)`
  const inserted = await sql`insert into test.test values(${ null })`
  await sql`drop table test.test`
  assert.strictEqual(inserted.count, 1)
})

test('Throws on illegal transactions', async () => {
  const sql = postgres({ ...options, max: 2, fetch_types: false })
  const error = await sql`begin`.catch(e => e)
  assert.strictEqual(error.code, 'UNSAFE_TRANSACTION')
})

test('Transaction throws', async () => {
  await sql`create table test.test (a int)`
  const error = await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql`insert into test.test values('hej')`
  }).catch(x => x)
  await sql`drop table test.test`
  assert.strictEqual(error.code, '22P02')
})

test('Transaction rolls back', async () => {
  await sql`create table test.test (a int)`
  await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql`insert into test.test values('hej')`
  }).catch(() => { /* ignore */ })
  const result = await sql`select a from test.test`
  await sql`drop table test.test`
  assert.strictEqual(result.count, 0)
})

test('Transaction throws on uncaught savepoint', async () => {
  await sql`create table test.test (a int)`
  const error = await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql.savepoint(async sql => {
      await sql`insert into test.test values(2)`
      throw new Error('fail')
    })
  }).catch(err => err.message)
  await sql`drop table test.test`
  assert.strictEqual(error, 'fail')
})

test('Transaction throws on uncaught named savepoint', async () => {
  await sql`create table test.test (a int)`
  const error = await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql.savepoit('watpoint', async sql => {
      await sql`insert into test.test values(2)`
      throw new Error('fail')
    })
  }).catch(() => 'fail')
  await sql`drop table test.test`
  assert.strictEqual(error, 'fail')
})

test('Transaction succeeds on caught savepoint', async () => {
  await sql`create table test.test (a int)`
  await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql.savepoint(async sql => {
      await sql`insert into test.test values(2)`
      throw new Error('please rollback')
    }).catch(() => { /* ignore */ })
    await sql`insert into test.test values(3)`
  })
  const result = await sql`select count(1) from test.test`
  await sql`drop table test.test`
  assert.strictEqual(result[0].count, '2')
})

test('Savepoint returns Result', async () => {
  let result
  await sql.begin(async sql => {
    result = await sql.savepoint(sql =>
      sql`select 1 as x`
    )
  })
  assert.strictEqual(result[0].x, 1)
})

test('Transaction requests are executed implicitly', async () => {
  const sql = postgres({ ...options, debug: true, idle_timeout: 1, fetch_types: false })
  const result = await sql.begin(sql => [
    sql`select set_config('postgres_js.test', 'testing', true)`,
    sql`select current_setting('postgres_js.test') as x`
  ])
  assert.strictEqual(result[1][0].x, 'testing')
})

test('Uncaught transaction request errors bubbles to transaction', async () => {
  const error = await sql.begin(sql => [
    sql`select wat`,
    sql`select current_setting('postgres_js.test') as x, ${ 1 } as a`
  ]).catch(e => e)
  assert.strictEqual(error.code, '42703')
})

test('Fragments in transactions', async () => {
  const result = await sql.begin(sql => sql`select true as x where ${ sql`1=1` }`)
  assert.strictEqual(result[0].x, true)
})

test('Transaction rejects with rethrown error', async () => {
  const error = await sql.begin(async sql => {
    try {
      await sql`select exception`
    } catch (ex) {
      throw new Error('WAT')
    }
  }).catch(e => e.message)
  assert.strictEqual(error, 'WAT')
})

test('Parallel transactions', async () => {
  await sql`create table test.test (a int)`
  const results = await Promise.all([
    sql.begin(sql => sql`select 1`),
    sql.begin(sql => sql`select 1`)
  ])
  await sql`drop table test.test`
  assert.strictEqual(results.map(x => x.count).join(''), '11')
})

test('Many transactions at beginning of connection', async () => {
  const sql = postgres(options)
  const xs = await Promise.all(Array.from({ length: 100 }, () => sql.begin(sql => sql`select 1`)))
  assert.strictEqual(xs.length, 100)
})

test('Transactions array', async () => {
  await sql`create table test.test (a int)`
  const results = await sql.begin(sql => [
    sql`select 1`.then(x => x),
    sql`select 1`
  ])
  await sql`drop table test.test`
  assert.strictEqual(results.map(x => x.count).join(''), '11')
})

test('Transaction waits', async () => {
  await sql`create table test.test (a int)`
  await sql.begin(async sql => {
    await sql`insert into test.test values(1)`
    await sql.savepoint(async sql => {
      await sql`insert into test.test values(2)`
      throw new Error('please rollback')
    }).catch(() => { /* ignore */ })
    await sql`insert into test.test values(3)`
  })
  const results = await Promise.all([
    sql.begin(sql => sql`select 1`),
    sql.begin(sql => sql`select 1`)
  ])
  await sql`drop table test.test`
  assert.strictEqual(results.map(x => x.count).join(''), '11')
})

test('Helpers in Transaction', async () => {
  const result = await sql.begin(async sql =>
    await sql`select ${ sql({ x: 1 }) }`
  )
  assert.strictEqual(result[0].x, '1')
})

test('Null sets to null', async () => { assert.strictEqual((await sql`select ${ null } as x`)[0].x, null) })

test('Throw syntax error', async () => { assert.strictEqual((await sql`wat 1`.catch(x => x)).code, '42601') })

test('Connect using uri', async () => {
  assert.strictEqual(await new Promise((resolve, reject) => {
    const sql = postgres(`postgres://${login.user}:${login.pass}@${options.host}:${options.port}/${options.db}`, {
      idle_timeout: CLIENT_TIMEOUT,
      prepare: options.prepare,
    })
    sql`select 1`.then(() => resolve(true), reject)
  }), true)
})

test('Options from uri with special characters in user and pass', async () => {
  const opt = postgres({ user: 'öla', pass: 'pass^word' }).options
  assert.strictEqual([opt.user, opt.pass].toString(), 'öla,pass^word')
})

test('Fail with proper error on no host', async () => {
  const error = await new Promise((resolve, reject) => {
    const sql = postgres('postgres://localhost:33333/' + options.db, {
      idle_timeout: CLIENT_TIMEOUT
    })
    sql`select 1`.then(reject, resolve)
  })
  assert.strictEqual(error.code, 'ECONNREFUSED')
})

test('Point type', async () => {
  const sql = postgres({
    ...options,
    types: {
      point: {
        to: 600,
        from: [600],
        serialize: ([x, y]) => '(' + x + ',' + y + ')',
        parse: (x) => x.slice(1, -1).split(',').map(x => +x)
      }
    }
  })

  await sql`create table test.test (x point)`
  await sql`insert into test.test (x) values (${ sql.types.point([10, 20]) })`
  const result = await sql`select x from test.test`
  await sql`drop table test.test`
  assert.strictEqual(result[0].x[1], 20)
})

test('Point type array', async () => {
  const sql = postgres({
    ...options,
    types: {
      point: {
        to: 600,
        from: [600],
        serialize: ([x, y]) => '(' + x + ',' + y + ')',
        parse: (x) => x.slice(1, -1).split(',').map(x => +x)
      }
    }
  })

  await sql`create table test.test (x point[])`
  await sql`insert into test.test (x) values (${ sql.array([sql.types.point([10, 20]), sql.types.point([20, 30])]) })`
  const result = await sql`select x from test.test`
  await sql`drop table test.test`
  assert.strictEqual(result[0].x[1][1], 30)
})

test('sql file', async () => {
  assert.strictEqual((await sql.file(rel('select.sql')))[0].x, 1)
})

test('sql file has forEach', async () => {
  let result
  await sql
    .file(rel('select.sql'), { cache: false })
    .forEach(({ x }) => result = x)

  assert.strictEqual(result, 1)
})

test('Parameters in file', async () => {
  const result = await sql.file(
    rel('select-param.sql'),
    ['hello']
  )
  assert.strictEqual(result[0].x, 'hello')
})

test('Connection ended promise', async () => {
  const sql = postgres(options)

  await sql.end()

  assert.strictEqual(await sql.end(), undefined)
})

test('Connection ended timeout', async () => {
  const sql = postgres(options)

  await sql.end({ timeout: 10 })

  assert.strictEqual(await sql.end(), undefined)
})

test('Connection end does not cancel query', async () => {
  const sql = postgres(options)

  const promise = sql`select 1 as x`.execute()

  await sql.end()

  assert.strictEqual((await promise)[0].x, 1)
})

test('unsafe', async () => {
  await sql`create table test.test (x int)`
  const result = await sql.unsafe('insert into test.test values ($1) returning *', [1])
  await sql`drop table test.test`
  assert.strictEqual(result[0].x, 1)
})

test('unsafe simple', async () => {
  assert.strictEqual((await sql.unsafe('select 1 as x'))[0].x, 1)
})

test('unsafe simple includes columns', async () => {
  assert.strictEqual((await sql.unsafe('select 1 as x').values()).columns[0].name, 'x')
})

test('unsafe describe', async () => {
  const q = 'insert into test.test values (1)'
  await sql`create table test.test(a int unique)`
  await sql.unsafe(q).describe()
  const x = await sql.unsafe(q).describe()
  await sql`drop table test.test`
  assert.strictEqual(x.string, q)
})

test('simple query using unsafe with multiple statements', async () => {
  assert.strictEqual((await sql.unsafe('select 1 as x;select 2 as x')).map(x => x[0].x).join(), '1,2')
})

test('simple query using simple() with multiple statements', async () => {
  assert.strictEqual((await sql`select 1 as x;select 2 as x`.simple()).map(x => x[0].x).join(), '1,2')
})

if (options.prepare && process.env.PGMODE != 'transaction') {
  test('listen and notify', async () => {
    const sql = postgres(options)
    const channel = 'hello'
    const result = await new Promise(async r => {
      await sql.listen(channel, r)
      sql.notify(channel, 'works')
    })

    await sql.end()
    assert.strictEqual(result, 'works')
  })

  test('double listen', async () => {
    const sql = postgres(options)
    , channel = 'hello'

    let count = 0

    await new Promise((resolve, reject) =>
      sql.listen(channel, resolve)
      .then(() => sql.notify(channel, 'world'))
      .catch(reject)
    ).then(() => count++)

    await new Promise((resolve, reject) =>
      sql.listen(channel, resolve)
      .then(() => sql.notify(channel, 'world'))
      .catch(reject)
    ).then(() => count++)

    // for coverage
    sql.listen('weee', () => { /* noop */ }).then(sql.end)

    assert.strictEqual(count, 2)
  })
}

test('big query body', { timeout: TEST_TIMEOUT * 2 }, async () => {
  const size = 50000
  await sql`create table test.test (x int)`
  const inserted = await sql`insert into test.test ${
    sql([...Array(size).keys()].map(x => ({ x })))
  }`
  await sql`drop table test.test`
  assert.strictEqual(inserted.count, size)
})

test('let postgres do implicit cast of unknown types', async () => {
  await sql`create table test.test (x timestamp with time zone)`
  const [{ x }] = await sql`insert into test.test values (${ new Date().toISOString() }) returning *`
  await sql`drop table test.test`
  assert.strictEqual(x instanceof Date, true)
})

test('only allows one statement', async () => {
  assert.strictEqual(await sql`select 1; select 2`.catch(e => e.code), '42601')
})

test('little bobby tables', async () => {
  const name = 'Robert\'); DROP TABLE students;--'

  await sql`create table test.students (name text, age int)`
  await sql`insert into test.students (name) values (${ name })`

  const selected = await sql`select name from test.students`
  await sql`drop table test.students`
  assert.strictEqual(selected[0].name, name)
})

test('Connection errors are caught using begin()', {
  timeout: TEST_TIMEOUT * 2
}, async () => {
  let error
  try {
    const sql = postgres({ host: 'localhost', port: 1 })

    await sql.begin(async (sql) => {
      await sql`insert into test (label, value) values (${1}, ${2})`
    })
  } catch (err) {
    error = err
  }

  assert.ok(error.code === 'ECONNREFUSED' || error.message === 'Connection refused (os error 61)')
})

test('dynamic table name', async () => {
  await sql`create table test.test(a int)`
  const selected = await sql`select * from ${ sql('test.test') }`
  await sql`drop table test.test`
  assert.strictEqual(selected.count, 0)
})

test('dynamic schema name', async () => {
  await sql`create table test.test(a int)`
  const selected = await sql`select * from ${ sql('test') }.test`
  await sql`drop table test.test`
  assert.strictEqual(selected.count, 0)
})

test('dynamic schema and table name', async () => {
  await sql`create table test.test(a int)`
  const selected = await sql`select * from ${ sql('test.test') }`
  await sql`drop table test.test`
  assert.strictEqual(selected.count, 0)
})

test('dynamic column name', async () => {
  const selected = await sql`select 1 as ${ sql('!not_valid') }`
  assert.strictEqual(Object.keys(selected[0])[0], '!not_valid')
})

test('dynamic select as', async () => {
  const selected = await sql`select ${ sql({ a: 1, b: 2 }) }`
  assert.strictEqual(selected[0].b, '2')
})

test('dynamic select as pluck', async () => {
  const selected = await sql`select ${ sql({ a: 1, b: 2 }, 'a') }`
  assert.strictEqual(selected[0].b, undefined)
})

test('dynamic insert', async () => {
  await sql`create table test.test (a int, b text)`
  const x = { a: 42, b: 'the answer' }

  const inserted = await sql`insert into test.test ${ sql(x) } returning *`
  await sql`drop table test.test`
  assert.strictEqual(inserted[0].b, 'the answer')
})

test('dynamic insert pluck', async () => {
  await sql`create table test.test (a int, b text)`
  const x = { a: 42, b: 'the answer' }

  const inserted = await sql`insert into test.test ${ sql(x, 'a') } returning *`
  await sql`drop table test.test`
  assert.strictEqual(inserted[0].b, null)
})

test('dynamic in with empty array', async () => {
  await sql`create table test.test (a int)`
  await sql`insert into test.test values (1)`
  const selected = await sql`select * from test.test where null in ${ sql([]) }`
  await sql`drop table test.test`
  assert.strictEqual(selected.count, 0)
})

test('dynamic in after insert', async () => {
  await sql`create table test.test (a int, b text)`
  const [{ x }] = await sql`
    with x as (
      insert into test.test values (1, 'hej')
      returning *
    )
    select 1 in ${ sql([1, 2, 3]) } as x from x
  `
  await sql`drop table test.test`
  assert.strictEqual(x, true)
})

test('array insert', async () => {
  await sql`create table test.test (a int, b int)`
  const inserted = await sql`insert into test.test (a, b) values ${ sql([1, 2]) } returning *`
  await sql`drop table test.test`
  assert.strictEqual(inserted[0].b, 2)
})

test('where parameters in()', async () => {
  await sql`create table test.test (x text)`
  await sql`insert into test.test values ('a')`
  const selected = await sql`select * from test.test where x in ${ sql(['a', 'b', 'c']) }`
  await sql`drop table test.test`
  assert.strictEqual(selected[0].x, 'a')
})

test('where parameters in() values before', async () => {
  const selected = await sql`
    with rows as (
      select * from (values (1), (2), (3), (4)) as x(a)
    )
    select * from rows where a in ${ sql([3, 4]) }
  `
  assert.strictEqual(selected.count, 2)
})

test('dynamic multi row insert', async () => {
  await sql`create table test.test (a int, b text)`
  const x = { a: 42, b: 'the answer' }

  const inserted = await sql`insert into test.test ${ sql([x, x]) } returning *`
  await sql`drop table test.test`
  assert.strictEqual(inserted[1].b, 'the answer')
})

test('dynamic update', async () => {
  await sql`create table test.test (a int, b text)`
  await sql`insert into test.test (a, b) values (17, 'wrong')`

  const updated = await sql`update test.test set ${ sql({ a: 42, b: 'the answer' }) } returning *`
  await sql`drop table test.test`
  assert.strictEqual(updated[0].b, 'the answer')
})

test('dynamic update pluck', async () => {
  await sql`create table test.test (a int, b text)`
  await sql`insert into test.test (a, b) values (17, 'wrong')`

  const updated = await sql`update test.test set ${ sql({ a: 42, b: 'the answer' }, 'a') } returning *`
  await sql`drop table test.test`
  assert.strictEqual(updated[0].b, 'wrong')
})

test('dynamic select array', async () => {
  await sql`create table test.test (a int, b text)`
  await sql`insert into test.test (a, b) values (42, 'yay')`
  const selected = await sql`select ${ sql(['a', 'b']) } from test.test`
  await sql`drop table test.test`
  assert.strictEqual(selected[0].b, 'yay')
})

test('dynamic returning array', async () => {
  await sql`create table test.test (a int, b text)`
  const inserted = await sql`insert into test.test (a, b) values (42, 'yay') returning ${ sql(['a', 'b']) }`
  await sql`drop table test.test`
  assert.strictEqual(inserted[0].b, 'yay')
})

test('dynamic select args', async () => {
  await sql`create table test.test (a int, b text)`
  await sql`insert into test.test (a, b) values (42, 'yay')`
  const selected = await sql`select ${ sql('a', 'b') } from test.test`
  await sql`drop table test.test`
  assert.strictEqual(selected[0].b, 'yay')
})

test('dynamic values single row', async () => {
  const [{ b }] = await sql`
    select * from (values ${ sql(['a', 'b', 'c']) }) as x(a, b, c)
  `

  assert.strictEqual(b, 'b')
})

test('dynamic values multi row', async () => {
  const [, { b }] = await sql`
    select * from (values ${ sql([['a', 'b', 'c'], ['a', 'b', 'c']]) }) as x(a, b, c)
  `

  assert.strictEqual(b, 'b')
})

test('Multiple queries', async () => {
  const sql = postgres({ ...options, max: 5 })
  const results = await Promise.all([
    sql`select 1`,
    sql`select 2`,
    sql`select 3`,
    sql`select 4`
  ])
  assert.strictEqual(results.length, 4)
})

test('Multiple statements', async () => {
  const results = await sql.unsafe(`
    select 1 as x;
    select 2 as a;
  `).then(([, [x]]) => x.a)
  assert.strictEqual(results, 2)
})

test('notice', async () => {
  let notice
  const log = console.log // eslint-disable-line
  console.log = function(x) { // eslint-disable-line
    notice = x
  }

  await sql`create table if not exists test.users()`
  await sql`create table if not exists test.users()`

  console.log = log // eslint-disable-line

  assert.strictEqual(notice.severity, 'NOTICE')
})

test('notice hook', async () => {
  let notice
  const sql = postgres({
    ...options,
    onnotice: x => notice = x
  })

  await sql`create table if not exists test.users()`
  await sql`create table if not exists test.users()`

  assert.strictEqual(notice.severity, 'NOTICE')
})

test('bytea serializes and parses', async () => {
  const buf = Buffer.from('wat')

  await sql`create table test.test (x bytea)`
  await sql`insert into test.test values (${ buf })`

  const selected = await sql`select x from test.test`
  await sql`drop table test.test`
  assert.strictEqual(selected[0].x.toString(), buf.toString())
})

test('forEach', async () => {
  let result
  await sql`select 1 as x`.forEach(({ x }) => result = x)
  assert.strictEqual(result, 1)
})

test('forEach returns empty array', async () => {
  const result = await sql`select 1 as x`.forEach(() => { /* noop */ })
  assert.strictEqual(result.length, 0)
})

if (process.env.PGMODE != 'transaction') {
  test('Cursor', async () => {
    const order = []
    await sql`select 1 as x union select 2 as x`.cursor(async([x]) => {
      order.push(x.x + 'a')
      await delay(100)
      order.push(x.x + 'b')
    })
    assert.strictEqual(order.join(''), '1a1b2a2b')
  })

  test('Unsafe cursor', async () => {
    const order = []
    await sql.unsafe('select 1 as x union select 2 as x').cursor(async([x]) => {
      order.push(x.x + 'a')
      await delay(100)
      order.push(x.x + 'b')
    })
    assert.strictEqual(order.join(''), '1a1b2a2b')
  })

  test('Cursor custom n', async () => {
    const order = []
    await sql`select * from generate_series(1,20)`.cursor(10, async(x) => {
      order.push(x.length)
    })
    assert.strictEqual(order.join(','), '10,10')
  })

  test('Cursor custom with rest n', async () => {
    const order = []
    await sql`select * from generate_series(1,20)`.cursor(11, async(x) => {
      order.push(x.length)
    })
    assert.strictEqual(order.join(','), '11,9')
  })

  test('Cursor custom with less results than batch size', async () => {
    const order = []
    await sql`select * from generate_series(1,20)`.cursor(21, async(x) => {
      order.push(x.length)
    })
    assert.strictEqual(order.join(','), '20')
  })

  test('Cursor cancel', async () => {
    let result
    await sql`select * from generate_series(1,10) as x`.cursor(async([{ x }]) => {
      result = x
      return sql.CLOSE
    })
    assert.strictEqual(result, 1)
  })

  test('Cursor throw', async () => {
    const order = []
    await sql`select 1 as x union select 2 as x`.cursor(async([x]) => {
      order.push(x.x + 'a')
      await delay(100)
      throw new Error('watty')
    }).catch(() => order.push('err'))
    assert.strictEqual(order.join(''), '1aerr')
  })

  test('Cursor error', async () => {
    assert.strictEqual(await sql`wat`.cursor(() => { /* noop */ }).catch((err) => err.code), '42601')
  })

  test('Multiple Cursors', { timeout: TEST_TIMEOUT * 2 }, async () => {
    const result = []
    await sql.begin(async sql => [
      await sql`select 1 as cursor, x from generate_series(1,4) as x`.cursor(async([row]) => {
        result.push(row.x)
        await new Promise(r => setTimeout(r, 20))
      }),
      await sql`select 2 as cursor, x from generate_series(101,104) as x`.cursor(async([row]) => {
        result.push(row.x)
        await new Promise(r => setTimeout(r, 10))
      })
    ])

    assert.strictEqual(result.join(','), '1,2,3,4,101,102,103,104')
  })

  test('Cursor as async iterator', async () => {
    const order = []
    for await (const [x] of sql`select generate_series(1,2) as x;`.cursor()) {
      order.push(x.x + 'a')
      await delay(10)
      order.push(x.x + 'b')
    }

    assert.strictEqual(order.join(''), '1a1b2a2b')
  })

  test('Cursor as async iterator with break', async () => {
    const order = []
    for await (const xs of sql`select generate_series(1,2) as x;`.cursor()) {
      order.push(xs[0].x + 'a')
      await delay(10)
      order.push(xs[0].x + 'b')
      break
    }

    assert.strictEqual(order.join(''), '1a1b')
  })

  test('Async Iterator Unsafe cursor', async () => {
    const order = []
    for await (const [x] of sql.unsafe('select 1 as x union select 2 as x').cursor()) {
      order.push(x.x + 'a')
      await delay(10)
      order.push(x.x + 'b')
    }
    assert.strictEqual(order.join(''), '1a1b2a2b')
  })

  test('Async Iterator Cursor custom n', async () => {
    const order = []
    for await (const x of sql`select * from generate_series(1,20)`.cursor(10))
    order.push(x.length)

    assert.strictEqual(order.join(','), '10,10')
  })

  test('Async Iterator Cursor custom with rest n', async () => {
    const order = []
    for await (const x of sql`select * from generate_series(1,20)`.cursor(11))
    order.push(x.length)

    assert.strictEqual(order.join(','), '11,9')
  })

  test('Async Iterator Cursor custom with less results than batch size', async () => {
    const order = []
    for await (const x of sql`select * from generate_series(1,20)`.cursor(21))
    order.push(x.length)
    assert.strictEqual(order.join(','), '20')
  })
}

test('Big result', async () => {
  assert.strictEqual((await sql`select * from generate_series(1, 100000)`).count, 100000)
})

test('bigint is returned as String', async () => {
  assert.strictEqual(typeof (await sql`select 9223372036854777 as x`)[0].x, 'string')
})

test('int is returned as Number', async () => {
  assert.strictEqual(typeof (await sql`select 123 as x`)[0].x, 'number')
})

test('numeric is returned as string', async () => {
  assert.strictEqual(typeof (await sql`select 1.2 as x`)[0].x, 'string')
})

test('connect_timeout', { timeout: TEST_TIMEOUT * 20 }, async () => {
  const connect_timeout = 0.2
  const server = net.createServer()
  server.listen()
  const sql = postgres({ port: server.address().port, host: '127.0.0.1', connect_timeout })
  const start = Date.now()
  let end
  await sql`select 1`.catch((e) => {
    if (e.code !== 'CONNECT_TIMEOUT')
      throw e
    end = Date.now()
  })
  server.close()
  assert.strictEqual(Math.floor((end - start) / 100) / 10, connect_timeout)
})

test('connect_timeout throws proper error', async () => {
  assert.strictEqual(await postgres({
    ...options,
    connect_timeout: 0.001
  })`select 1`.catch(e => e.code), 'CONNECT_TIMEOUT')
})

test('connect_timeout error message includes host:port', { timeout: TEST_TIMEOUT * 20 }, async () => {
  const connect_timeout = 0.2
  const server = net.createServer()
  server.listen()
  const sql = postgres({ port: server.address().port, host: '127.0.0.1', connect_timeout })
  const port = server.address().port
  let err
  await sql`select 1`.catch((e) => {
    if (e.code !== 'CONNECT_TIMEOUT')
      throw e
    err = e.message
  })
  server.close()
  assert.strictEqual(err, ['write CONNECT_TIMEOUT 127.0.0.1:', port].join(''))
})

test('requests works after single connect_timeout', async () => {
  let first = true

  const sql = postgres({
    ...options,
    connect_timeout: { valueOf() { return first ? (first = false, 0.0001) : CLIENT_TIMEOUT } }
  })

  assert.strictEqual(
    [
      await sql`select 1 as x`.then(() => 'success', x => x.code),
      await delay(10),
      (await sql`select 1 as x`)[0].x
    ].join(','),
    'CONNECT_TIMEOUT,,1'
  )
})

test('Result has columns spec', async () => {
  assert.strictEqual((await sql`select 1 as x`).columns[0].name, 'x')
})

test('forEach has result as second argument', async () => {
  let x
  await sql`select 1 as x`.forEach((_, result) => x = result)
  assert.strictEqual(x.columns[0].name, 'x')
})

test('Result as arrays', async () => {
  const sql = postgres({
    ...options,
    transform: {
      row: x => Object.values(x)
    }
  })

  assert.strictEqual((await sql`select 1 as a, 2 as b`)[0].join(','), '1,2')
})

test('Insert empty array', async () => {
  await sql`create table test.tester (ints int[])`
  const result = (await sql`insert into test.tester (ints) values (${ sql.array([]) }) returning *`)[0].ints
  await sql`drop table test.tester`
  assert.strictEqual(Array.isArray(result), true)
})

test('Insert array in sql()', async () => {
  await sql`create table test.tester (ints int[])`
  const result = (await sql`insert into test.tester ${ sql({ ints: sql.array([]) }) } returning *`)[0].ints
  await sql`drop table test.tester`
  assert.strictEqual(Array.isArray(result), true)
})

if (options.prepare) {
  test('Automatically creates prepared statements', async () => {
    const result = await sql`select * from pg_prepared_statements`
    assert.strictEqual(result.some(x => x.name = result.statement.name), true)
  })

  test('no_prepare: true disables prepared statements (deprecated)', async () => {
    const sql = postgres({ ...options, no_prepare: true })
    const result = await sql`select * from pg_prepared_statements`
    assert.strictEqual(result.some(x => x.name = result.statement.name), false)
  })

  test('prepare: false disables prepared statements', async () => {
    const sql = postgres({ ...options, prepare: false })
    const result = await sql`select * from pg_prepared_statements`
    assert.strictEqual(result.some(x => x.name = result.statement.name), false)
  })

  test('prepare: true enables prepared statements', async () => {
    const sql = postgres({ ...options, prepare: true })
    const result = await sql`select * from pg_prepared_statements`
    assert.strictEqual(result.some(x => x.name = result.statement.name), true)
  })

  test('prepares unsafe query when "prepare" option is true', async () => {
    const sql = postgres({ ...options, prepare: true })
    const result = await sql.unsafe('select * from pg_prepared_statements where name <> $1', ['bla'], { prepare: true })
    assert.strictEqual(result.some(x => x.name = result.statement.name), true)
  })

  test('does not prepare unsafe query by default', async () => {
    const sql = postgres({ ...options, prepare: true })
    const result = await sql.unsafe('select * from pg_prepared_statements where name <> $1', ['bla'])
    assert.strictEqual(result.some(x => x.name = result.statement.name), false)
  })

  test('Recreate prepared statements on transformAssignedExpr error', async () => {
    const insert = () => sql`insert into test.test (name) values (${ '1' }) returning name`
    await sql`create table test.test (name text)`
    await insert()
    await sql`alter table test.test alter column name type int using name::integer`
    const inserted = await insert()
    await sql`drop table test.test`
    assert.strictEqual(inserted[0].name, 1)
  })
}

test('Throws correct error when retrying in transactions', async () => {
  await sql`create table test.test(x int)`
  const error = await sql.begin(sql => sql`insert into test.test (x) values (${ false })`).catch(e => e)
  await sql`drop table test.test`
  assert.strictEqual(error.code, '42804')
})

test('Recreate prepared statements on RevalidateCachedQuery error', async () => {
  const select = () => sql`select name from test.test`
  await sql`create table test.test (name text)`
  await sql`insert into test.test values ('1')`
  await select()
  await sql`alter table test.test alter column name type int using name::integer`
  const selected = await select()
  await sql`drop table test.test`
  assert.strictEqual(selected[0].name, 1)
})

test('Properly throws routine error on not prepared statements', async () => {
  await sql`create table test.x (x text[])`
  const { routine } = await sql.unsafe(`
    insert into test.x(x) values (('a', 'b'))
  `).catch(e => e)

  await sql`drop table test.x`
  assert.strictEqual(routine, 'transformAssignedExpr')
})

test('Properly throws routine error on not prepared statements in transaction', async () => {
  const { routine } = await sql.begin(sql => [
    sql`create table test.x (x text[])`,
    sql`insert into test.x(x) values (('a', 'b'))`
  ]).catch(e => e)

  assert.strictEqual(routine, 'transformAssignedExpr')
})

test('Properly throws routine error on not prepared statements using file', async () => {
  const { routine } = await sql.unsafe(`
    create table test.x (x text[]);
    insert into test.x(x) values (('a', 'b'));
  `, { prepare: true }).catch(e => e)

  assert.strictEqual(routine, 'transformAssignedExpr')
})

test('Escaping supports schemas and tables', async () => {
  await sql`create schema a`
  await sql`create table a.b (c int)`
  await sql`insert into a.b (c) values (1)`
  const selected = await sql`select ${ sql('a.b.c') } from a.b`
  await sql`drop table a.b`
  await sql`drop schema a`
  assert.strictEqual(selected[0].c, 1)
})

test('Raw method returns rows as arrays', async () => {
  const [x] = await sql`select 1`.raw()
  assert.strictEqual(Array.isArray(x), true)
})

test('Raw method returns values unparsed as Buffer', async () => {
  const [[x]] = await sql`select 1`.raw()
  assert.strictEqual(x instanceof Uint8Array, true)
})

test('Array returns rows as arrays of columns', async () => {
  assert.strictEqual((await sql`select 1`.values())[0][0], 1)
})

test('Copy read', async () => {
  const result = []

  await sql`create table test.test (x int)`
  await sql`insert into test.test select * from generate_series(1,10)`
  const readable = await sql`copy test.test to stdout`.readable()
  readable.on('data', x => result.push(x))
  await new Promise(r => readable.on('end', r))

  await sql`drop table test.test`
  assert.strictEqual(result.length, 10)
})

test('Copy write', { timeout: TEST_TIMEOUT * 2 }, async () => {
  await sql`create table test.test (x int)`
  const writable = await sql`copy test.test from stdin`.writable()

  writable.write('1\n')
  writable.write('1\n')
  writable.end()

  await new Promise(r => writable.on('finish', r))

  const selected = await sql`select 1 from test.test`
  await sql`drop table test.test`
  assert.strictEqual(selected.length, 2)
})

test('Copy write as first', async () => {
  await sql`create table test.test (x int)`
  const first = postgres(options)
  const writable = await first`COPY test.test FROM STDIN WITH(FORMAT csv, HEADER false, DELIMITER ',')`.writable()
  writable.write('1\n')
  writable.write('1\n')
  writable.end()

  await new Promise(r => writable.on('finish', r))

  const selected = await sql`select 1 from test.test`
  await sql`drop table test.test`
  assert.strictEqual(selected.length, 2)
})

test('Copy from file', async () => {
  await sql`create table test.test (x int, y int, z int)`
  await new Promise(async r => fs
    .createReadStream(rel('copy.csv'))
    .pipe(await sql`copy test.test from stdin`.writable())
    .on('finish', r)
  )

  const selected = await sql`select * from test.test`
  await sql`drop table test.test`
  assert.strictEqual(JSON.stringify(selected), '[{"x":1,"y":2,"z":3},{"x":4,"y":5,"z":6}]')
})

test('Copy from works in transaction', async () => {
  await sql`create table test.test(x int)`
  const xs = await sql.begin(async sql => {
    (await sql`copy test.test from stdin`.writable()).end('1\n2')
    await delay(20)
    return sql`select 1 from test.test`
  })

  await sql`drop table test.test`
  assert.strictEqual(xs.length, 2)
})

test('Copy from abort', async () => {
  const sql = postgres(options)
  const readable = fs.createReadStream(rel('copy.csv'))

  await sql`create table test.test (x int, y int, z int)`
  await sql`TRUNCATE TABLE test.test`

  const writable = await sql`COPY test.test FROM STDIN`.writable()

  let aborted

  readable
    .pipe(writable)
    .on('error', (err) => aborted = err)

  writable.destroy(new Error('abort'))
  await sql.end()

  await postgres(options)`drop table test.test`
  assert.strictEqual(aborted.message, 'abort')
})

test('multiple queries before connect', async () => {
  const sql = postgres({ ...options, max: 2 })
  const xs = await Promise.all([
    sql`select 1 as x`,
    sql`select 2 as x`,
    sql`select 3 as x`,
    sql`select 4 as x`
  ])

  assert.strictEqual(xs.map(x => x[0].x).join(), '1,2,3,4')
})

test('Execute', async () => {
  const result = await new Promise((resolve) => {
    const sql = postgres({ ...options, fetch_types: false, debug:(id, query) => resolve(query) })
    sql`select 1`.execute()
  })

  assert.strictEqual(result, 'select 1')
})

test('Cancel running query', async () => {
  const query = sql`select pg_sleep(2)`
  setTimeout(() => query.cancel(), 500)
  const error = await query.catch(x => x)
  assert.strictEqual(error.code, '57014')
})

test('Cancel piped query', { timeout: TEST_TIMEOUT * 2 }, async () => {
  const sql = postgres({...options, max: 2})
  await sql`select 1`
  const last = sql`select pg_sleep(1)`.execute()
  const query = sql`select pg_sleep(2) as dig`
  setTimeout(() => query.cancel(), 500)
  const error = await query.catch(x => x)
  await last
  assert.strictEqual(error.code, '57014')
})

test('Cancel queued query', async () => {
  const query = sql`select pg_sleep(2) as nej`
  const tx = sql.begin(sql => (
    query.cancel(),
    sql`select pg_sleep(0.5) as hej, 'hejsa'`
  ))
  const error = await query.catch(x => x)
  await tx
  assert.strictEqual(error.code, '57014')
})

test('Fragments', async () => {
  assert.strictEqual((await sql`
    ${ sql`select` } 1 as x
  `)[0].x, 1)
})

test('Result becomes array', async () => {
  assert.strictEqual((await sql`select 1`).slice() instanceof Array, true)
})

test('Describe', async () => {
  const type = (await sql`select ${ 1 }::int as x`.describe()).types[0]
  assert.strictEqual(type, 23)
})

test('Describe a statement', async () => {
  await sql`create table test.tester (name text, age int)`
  const r = await sql`select name, age from test.tester where name like $1 and age > $2`.describe()
  await sql`drop table test.tester`
  assert.strictEqual(`${ r.types.join(',') }/${ r.columns.map(c => `${c.name}:${c.type}`).join(',') }`, '25,23/name:25,age:23')
})

test('Include table oid and column number in column details', async () => {
  await sql`create table test.tester (name text, age int)`
  const r = await sql`select name, age from test.tester where name like $1 and age > $2`.describe()
  const [{ oid }] = await sql`select oid from pg_class where relname = 'tester'`
  await sql`drop table test.tester`

  assert.strictEqual(`${ r.columns.map(c => `table:${c.table},number:${c.number}`).join('|') }`, `table:${oid},number:1|table:${oid},number:2`)
})

test('Describe a statement without parameters', async () => {
  await sql`create table test.tester (name text, age int)`
  const r = await sql`select name, age from test.tester`.describe()
  await sql`drop table test.tester`
  assert.strictEqual(`${ r.types.length },${ r.columns.length }`, '0,2')
})

test('Describe a statement without columns', async () => {
  await sql`create table test.tester (name text, age int)`
  const r = await sql`insert into test.tester (name, age) values ($1, $2)`.describe()
  await sql`drop table test.tester`
  assert.strictEqual(`${ r.types.length },${ r.columns.length }`, '2,0')
})

test('Large object', async () => {
  const file = rel('index.test.js')
      , md5 = crypto.createHash('md5').update(fs.readFileSync(file)).digest('hex')

  const lo = await sql.largeObject()
  await new Promise(async r => fs.createReadStream(file).pipe(await lo.writable()).on('finish', r))
  await lo.seek(0)

  const out = crypto.createHash('md5')
  await new Promise(r => lo.readable().then(x => x.on('data', x => out.update(x)).on('end', r)))

  const digest = out.digest('hex')
  await lo.close()
  assert.strictEqual(digest, md5)
})

test('Catches type serialize errors', async () => {
  const sql = postgres({
    ...options,
    idle_timeout: CLIENT_TIMEOUT,
    types: {
      text: {
        from: 25,
        to: 25,
        parse: x => x,
        serialize: () => { throw new Error('watSerialize') }
      }
    }
  })

  assert.strictEqual((await sql`select ${ 'wat' }`.catch(e => e.message)), 'watSerialize')
})

test('Catches type parse errors', async () => {
  const sql = postgres({
    ...options,
    idle_timeout: CLIENT_TIMEOUT,
    types: {
      text: {
        from: 25,
        to: 25,
        parse: () => { throw new Error('watParse') },
        serialize: x => x
      }
    }
  })

  assert.strictEqual((await sql`select 'wat'`.catch(e => e.message)), 'watParse')
})

test('Catches type serialize errors in transactions', async () => {
  const sql = postgres({
    ...options,
    idle_timeout: CLIENT_TIMEOUT,
    types: {
      text: {
        from: 25,
        to: 25,
        parse: x => x,
        serialize: () => { throw new Error('watSerialize') }
      }
    }
  })

  assert.strictEqual((await sql.begin(sql => (
    sql`select 1`,
    sql`select ${ 'wat' }`
  )).catch(e => e.message)), 'watSerialize')
})

test('Catches type parse errors in transactions', async () => {
  const sql = postgres({
    ...options,
    idle_timeout: CLIENT_TIMEOUT,
    types: {
      text: {
        from: 25,
        to: 25,
        parse: () => { throw new Error('watParse') },
        serialize: x => x
      }
    }
  })

  assert.strictEqual((await sql.begin(sql => (
    sql`select 1`,
    sql`select 'wat'`
  )).catch(e => e.message)), 'watParse')
})

test('Prevent premature end of connection in transaction', async () => {
  const sql = postgres({...options, max_lifetime: 0.01, idle_timeout: CLIENT_TIMEOUT })
  const result = await sql.begin(async sql => {
    await sql`select 1`
    await delay(20)
    await sql`select 1`
    return 'yay'
  })

  assert.strictEqual(result, 'yay')
})

test('Ensure reconnect after max_lifetime with transactions', { timeout: TEST_TIMEOUT * 5 }, async () => {
  const sql = postgres({
    ...options,
    max_lifetime: 0.01,
    idle_timeout: CLIENT_TIMEOUT,
    max: 1
  })

  let x = 0
  while (x++ < 10) await sql.begin(sql => sql`select 1 as x`)

  assert.ok(true)
})

test('Ensure drain only dequeues if ready', async () => {
  const sql = postgres(options)

  const res = await Promise.all([
    sql.unsafe('SELECT 0+$1 --' + '.'.repeat(100000), [1]),
    sql.unsafe('SELECT 0+$1+$2+$3', [1, 2, 3])
  ])

  assert.strictEqual(res.length, 2)
})

test('Supports fragments as dynamic parameters', async () => {
  await sql`create table test.test (a int, b bool)`
  await sql`insert into test.test values(1, true)`
  await sql`insert into test.test ${
    sql({
      a: 2,
      b: sql`exists(select 1 from test.test where b = ${ true })`
    })
  }`

  const result = (await sql`select * from test.test`.raw()).join('')
  await sql`drop table test.test`
  assert.strictEqual(result, '1,t2,t')
})

test('Supports nested fragments with parameters', async () => {
  await sql`create table test.test ${
    sql`(${ sql('a') } ${ sql`int` })`
  }`
  await sql`insert into test.test values(1)`
  const value = (await sql`select a from test.test`)[0].a
  await sql`drop table test.test`
  assert.strictEqual(value, 1)
})

test('Supports multiple nested fragments with parameters', async () => {
  const [{ b }] = await sql`select * ${
    sql`from ${
      sql`(values (2, ${ 1 }::int)) as x(${ sql(['a', 'b']) })`
    }`
  }`
  assert.strictEqual(b, 1)
})

test('Supports arrays of fragments', async () => {
  const [{ x }] = await sql`
    ${ [sql`select`, sql`1`, sql`as`, sql`x`] }
  `

  assert.strictEqual(x, 1)
})

test('Does not try rollback when commit errors', async () => {
  let notice = null
  const sql = postgres({ ...options, onnotice: x => notice = x })
  await sql`create table test.test(x int constraint test_constraint unique deferrable initially deferred)`

  await sql.begin('isolation level serializable', async sql => {
    await sql`insert into test.test values(1)`
    await sql`insert into test.test values(1)`
  }).catch(e => e)

  await sql`drop table test.test`
  assert.strictEqual(notice, null)
})

test('Last keyword used even with duplicate keywords', async () => {
  await sql`create table test.test (x int)`
  await sql`insert into test.test values(1)`
  const [{ x }] = await sql`
    select
      1 in (1) as x
    from test.test
    where x in ${ sql([1, 2]) }
  `

  await sql`drop table test.test`
  assert.strictEqual(x, true)
})

test('Insert array with null', async () => {
  await sql`create table test.test (x int[])`
  await sql`insert into test.test ${ sql({ x: [1, null, 3] }) }`
  const value = (await sql`select x from test.test`)[0].x[0]
  await sql`drop table test.test`
  assert.strictEqual(value, 1)
})

test('concurrent cursors', async () => {
  const xs = []

  await Promise.all([...Array(7)].map((x, i) => [
    sql`select ${ i }::int as a, generate_series(1, 2) as x`.cursor(([x]) => xs.push(x.a + x.x))
  ]).flat())

  assert.strictEqual(xs.join(''), '12233445566778')
})

test('concurrent cursors multiple connections', async () => {
  const sql = postgres({ ...options, max: 2 })
  const xs = []

  await Promise.all([...Array(7)].map((x, i) => [
    sql`select ${ i }::int as a, generate_series(1, 2) as x`.cursor(([x]) => xs.push(x.a + x.x))
  ]).flat())

  assert.strictEqual(xs.sort().join(''), '12233445566778')
})

if (process.env.PGMODE != 'transaction') {
  test('reserve connection', async () => {
    const reserved = await sql.reserve()

    setTimeout(() => reserved.release(), 510)

    const xs = await Promise.all([
      reserved`select 1 as x`.then(([{ x }]) => ({ time: Date.now(), x })),
      sql`select 2 as x`.then(([{ x }]) => ({ time: Date.now(), x })),
      reserved`select 3 as x`.then(([{ x }]) => ({ time: Date.now(), x }))
    ])

    if (xs[1].time - xs[2].time < 500)
      throw new Error('Wrong time')

    assert.strictEqual(xs.map(x => x.x).join(''), '123')
  })
}

test('arrays in reserved connection', async () => {
  const reserved = await sql.reserve()
  const [{ x }] = await reserved`select array[1, 2, 3] as x`
  reserved.release()

  assert.strictEqual(x.join(''), '123')
})
