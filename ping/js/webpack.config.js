import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const source = path.resolve(__dirname, 'src')

export default {
  context: __dirname,
  entry: './src/index.js',
  output: {
    path: path.resolve(__dirname, 'runtime', 'server', 'static', 'assets'),
    filename: 'plan.bundle.js',
    library: '$',
    libraryTarget: 'umd'
  },
  module: {
    rules: [{
      test: /\.(js)$/,
      exclude: /node_modules/,
      include: source,
      use: 'babel-loader'
    }]
  },
  mode: 'development'
}
