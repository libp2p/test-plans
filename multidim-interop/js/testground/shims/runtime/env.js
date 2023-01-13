export async function getParams () {
  try {
    return window.testground.env
  } catch (_) {
    return {}
  }
}

export const IS_BROWSER = true