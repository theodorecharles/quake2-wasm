#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { createReadStream, statSync, writeFileSync } from 'node:fs';
import { basename, relative, resolve } from 'node:path';

async function sha256(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

async function describe(file, path) {
  const stats = statSync(file);
  if (!stats.isFile()) throw new Error(`Not a regular file: ${file}`);
  return { path, size: stats.size, sha256: await sha256(file) };
}

async function writeBundle(output, kind, toolchain, sourceDateEpoch, containsRetailData, files) {
  const artifacts = [];
  for (const file of files) artifacts.push(await describe(file, basename(file)));
  const manifest = {
    schemaVersion: 1,
    kind,
    toolchain,
    sourceDateEpoch: Number(sourceDateEpoch),
    containsRetailData: containsRetailData === 'true',
    artifacts
  };
  writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
}

async function writeData(output, dataDirectory, files) {
  const assets = [];
  for (const file of files) {
    const assetPath = `baseq2/${relative(dataDirectory, file)}`;
    assets.push(await describe(file, assetPath));
  }
  const manifest = { schemaVersion: 1, kind: 'quake2-retail-data', assets };
  writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
}

const [mode, ...args] = process.argv.slice(2);

if (mode === 'bundle') {
  if (args.length < 6) throw new Error('bundle requires output, kind, toolchain, epoch, retail flag, and files');
  await writeBundle(resolve(args[0]), args[1], args[2], args[3], args[4],
                    args.slice(5).map((file) => resolve(file)));
} else if (mode === 'data') {
  if (args.length < 3) throw new Error('data requires output, data directory, and files');
  await writeData(resolve(args[0]), resolve(args[1]),
                  args.slice(2).map((file) => resolve(file)));
} else {
  throw new Error('usage: write-manifest.mjs bundle|data ...');
}
