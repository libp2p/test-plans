#!/usr/bin/env node

// Computes the cache key for a given implementation family and version.
// Replicates the hashing logic from helpers/cache.ts.
//
// Usage: node compute-cache-key.mjs <family> <version>
// Example: node compute-cache-key.mjs go v0.45

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { createRequire } from 'node:module';

const family = process.argv[2];
const version = process.argv[3];

if (!family || !version) {
  console.error('Usage: node compute-cache-key.mjs <family> <version>');
  process.exit(1);
}

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const root = path.resolve(scriptDir, '..', '..', 'transport-interop');

// Resolve 'ignore' from transport-interop/node_modules
const require = createRequire(path.join(root, 'package.json'));
const ignore = require('ignore');

const implFamilyDir = path.join(root, 'impl', family);
const implFolder = fs.realpathSync(path.join(implFamilyDir, version));

if (!fs.statSync(implFolder).isDirectory()) {
  console.error(`Not a directory: ${implFolder}`);
  process.exit(1);
}

// Build ignore filter — same order as helpers/cache.ts
const ig = ignore();
addGitignoreIfPresent(ig, path.join(root, '.gitignore'));
addGitignoreIfPresent(ig, path.join(root, '..', '.gitignore'));
addGitignoreIfPresent(ig, path.join(implFamilyDir, '.gitignore'));
addGitignoreIfPresent(ig, path.join(implFolder, '.gitignore'));

// Walk, filter, sort — same as helpers/cache.ts
let files = walkDir(implFolder);
files = files.map(f => f.replace(implFolder + '/', ''));
files = files.filter(ig.createFilter());
files.sort();

// Hash
files = files.map(f => path.join(implFolder, f));
const cacheKey = await hashFiles(files);
console.log(cacheKey);

function walkDir(dir) {
  let results = [];
  for (const f of fs.readdirSync(dir)) {
    const dirPath = path.join(dir, f);
    if (fs.statSync(dirPath).isDirectory()) {
      results = results.concat(walkDir(dirPath));
    } else {
      results.push(dirPath);
    }
  }
  return results;
}

async function hashFiles(files) {
  const fileHashes = await Promise.all(
    files.map(async (file) => {
      const data = await fs.promises.readFile(file);
      return crypto.createHash('sha256').update(data).digest('hex');
    })
  );
  return crypto.createHash('sha256').update(fileHashes.join('')).digest('hex');
}

function addGitignoreIfPresent(ig, filePath) {
  try {
    if (fs.statSync(filePath).isFile()) {
      ig.add(fs.readFileSync(filePath, 'utf8'));
    }
  } catch {
    // File doesn't exist, skip
  }
}
