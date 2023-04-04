#! /usr/bin/env ts-node-esm

import { execSync } from 'child_process';
import * as fs from 'fs';

const cacheKey = execSync('git ls-files | tr "\n" " " | xargs ../../helpers/hashFiles.sh').toString().trim();

function shouldUseCache(imageName: string): boolean {
  try {
    execSync(`IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/shouldUseCache.sh`, { stdio: 'inherit' });
    return true;
  } catch (e) {
    return false;
  }
}

function buildImage(imageName: string, dockerfile: string) {
  if (shouldUseCache(imageName)) {
    console.log('Using cache');
    execSync(`CACHE_KEY=${cacheKey} IMAGE_NAME=${imageName} ../../helpers/tryLoadCache.sh`, { stdio: 'inherit' });
  } else {
    execSync(`docker build -t ${imageName} -f ${dockerfile} .`, { stdio: 'inherit' });

    if (process.env.CI !== undefined && process.env.CI !== '') {
      execSync(`IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/saveCache.sh`, { stdio: 'inherit' });
    }
  }

  const imageHash = execSync(`docker image inspect ${imageName} -f "{{.Id}}"`).toString().trim();
  fs.writeFileSync(`${imageName}-image.json`, JSON.stringify({ imageID: imageHash }));
}

function main(imageName: string, dockerfile: string = 'Dockerfile') {
  buildImage(imageName, dockerfile);
}

const args = process.argv.slice(2);
const imageName = args[0];
const dockerfile = args[1];
main(imageName, dockerfile);

export {}
