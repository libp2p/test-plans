export async function markTestAsCompleted (name, result) {
  console.info(`marking browser test ${name} as completed: (${result})`)
  window.testground.result = result
}
