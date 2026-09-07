// SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
// SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: EUPL-1.2

/* eslint no-console: 0 */

import util from 'node:util'

let done = 0
let only = false
let ignored = 0
let failed = false
let promise = Promise.resolve()
let testNumber = 0
const tests = {}
    , ignore = Symbol('ignore')

const failFast = !!process.env.FAIL_FAST

export const nt = () => ignored++
export const ot = (...rest) => (only = true, test(true, ...rest))
export const t = (...rest) => test(false, ...rest)
t.timeout = (process.env.TIMEOUT || 5) | 0

async function test(o, name, options, fn) {
  typeof options !== 'object' && (fn = options, options = {})
  const line = ++testNumber

  await 1

  if (only && !o)
    return

  tests[line] = { fn, line, name }
  promise = promise.then(() => Promise.race([
    new Promise((resolve, reject) =>
      fn.timer = setTimeout(() => reject('Timed out'), (options.timeout || t.timeout) * 1000)
    ),
    (failed && failFast) ? (ignored++, ignore) : (function() {
      process.stdout.write(`${name}: `)
      return fn()
    })()
  ]))
    .then(async x => {
      clearTimeout(fn.timer)
      if (x === ignore)
        return

      if (!Array.isArray(x))
        throw new Error('Test should return result array')

      const [expected, got] = await Promise.all(x)
      if (expected !== got) {
        failed = true
        throw new Error(util.inspect(expected) + ' != ' + util.inspect(got))
      }

      tests[line].succeeded = true
      process.stdout.write('✅\n')
    })
    .catch(err => {
      process.stdout.write('⛔️')
      tests[line].failed = failed = true
      tests[line].error = err instanceof Error ? err : new Error(util.inspect(err))
      console.error(name + ' at line', line, 'failed\n', util.inspect(err))
    })
    .then(() => {
      ++done === Object.keys(tests).length && exit()
    })
}

function exit() {
  let success = true
  Object.values(tests).every((x) => {
    if (x.succeeded)
      return true

    success = false
  })

  only
    ? console.error('⚠️', 'Not all tests were run')
    : ignored
      ? console.error('⚠️', ignored, 'ignored test' + (ignored === 1 ? '' : 's'), '\n')
      : success
        ? console.log('🎉')
        : console.error('⚠️', 'Not good')

  if (!success || only || ignored) { process.exit(1) } else { process.exit(0) }
}

