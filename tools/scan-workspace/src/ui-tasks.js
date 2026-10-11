// A file read, model parse and state replacement are one operation. Lock before
// the first await so a second import cannot finish first and then be overwritten.
export function createTaskRunner(onBusy = () => {}) {
  let active = false;
  return {
    get busy() { return active; },
    async run(action) {
      if (active) return false;
      active = true;
      try {
        onBusy(true);
        await action();
        return true;
      } finally {
        active = false;
        onBusy(false);
      }
    }
  };
}
