'use strict'

const winston = require('winston')
const path = require('path')

/**
 * @param {import('./params').RunParams} params
 * @returns {winston.Logger}
 */
function getLogger (params) {
  const format = winston.format.combine(
    winston.format((info, opts = {}) => {
      info.ts = Date.now() * 1000000 // timestamp with nanoseconds, doesn't have precision,
      info.group_id = params.testGroupId
      info.run_id = params.testRun
      return info
    })(),
    winston.format.json()
  )

  const transports = [
    new winston.transports.Console({ format }),
    new winston.transports.File({ filename: 'stdout', format })
  ]

  if (params.testOutputsPath) {
    transports.push(new winston.transports.File({
      format,
      filename: path.join(params.testOutputsPath, 'run.out')
    }))
  }

  return winston.createLogger({
    level: process.env.LOG_LEVEL !== ''
      ? process.env.LOG_LEVEL
      : 'info',
    format,
    transports
  })
}

module.exports = {
  getLogger
}
