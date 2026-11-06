// Supervizor: pornește relay-ul și îl repornește automat dacă se oprește
// neașteptat (pentru LIVE-uri de mai multe ore). Pornire: npm run start:live
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const serverPath = path.join(path.dirname(fileURLToPath(import.meta.url)), 'server.js');
let restarts = 0;
let lastStart = 0;
let child = null;
let stopping = false;

function start() {
  lastStart = Date.now();
  child = spawn(process.execPath, [serverPath], { stdio: 'inherit' });
  child.on('exit', (code, signal) => {
    if (stopping) return process.exit(0);
    // dacă a rulat mult timp, resetăm contorul de reporniri
    if (Date.now() - lastStart > 5 * 60 * 1000) restarts = 0;
    restarts += 1;
    const delay = Math.min(30000, 1000 * 2 ** Math.min(restarts, 5));
    console.error(`[supervisor] relay oprit (cod ${code ?? signal}). Repornire #${restarts} în ${delay / 1000}s`);
    setTimeout(start, delay);
  });
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    stopping = true;
    child?.kill(sig);
    setTimeout(() => process.exit(0), 3000).unref();
  });
}

start();
