import { WebSocket } from 'ws';

/** One-line description of an event, used to compare streams in tests. */
export function summarize(e) {
  if (e.type === 'tool_start') return `tool_start:${e.category}:${e.target ?? ''}`;
  if (e.type === 'tool_end') return e.ok === false ? 'tool_end(fail)' : 'tool_end';
  return e.type;
}

export function connectWs(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const messages = [];
    const waiters = [];
    socket.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      const waiter = waiters.shift();
      if (waiter) waiter(msg);
      else messages.push(msg);
    });
    socket.on('error', reject);
    socket.on('open', () =>
      resolve({
        socket,
        next: () =>
          new Promise((res, rej) => {
            if (messages.length) return res(messages.shift());
            const timer = setTimeout(() => rej(new Error('timed out waiting for a message')), 3000);
            waiters.push((m) => {
              clearTimeout(timer);
              res(m);
            });
          }),
      }),
    );
  });
}
