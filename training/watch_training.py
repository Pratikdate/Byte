"""Live, readable view of an mlx_lm LoRA training log.

Usage: python3 watch_training.py [log_file]   (default: train_1b.log)   Ctrl-C to quit.
"""
import os
import re
import sys
import time

LOG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "train_1b.log")
TRAIN = re.compile(r"Iter (\d+): Train loss ([\d.]+).*?It/sec ([\d.]+).*?Peak mem ([\d.]+) GB")
VAL = re.compile(r"Iter (\d+): Val loss ([\d.]+)")
TOTAL = re.compile(r"iters: (\d+)")


def bar(done: int, total: int, width: int = 28) -> str:
    filled = int(width * done / max(total, 1))
    return "█" * filled + "░" * (width - filled)


def fmt_eta(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m" if h else f"{m}m {s:02d}s"


def main() -> None:
    total, first_loss, best_val = 1200, None, None
    print(f"📈 Watching {LOG}  (Ctrl-C to stop watching; training keeps running)\n")
    with open(LOG, "r", errors="replace") as f:
        buf = ""
        while True:
            chunk = f.read()
            if not chunk:
                time.sleep(1)
                continue
            buf += chunk.replace("\r", "\n")
            *lines, buf = buf.split("\n")
            for line in lines:
                if m := TOTAL.search(line):
                    total = int(m.group(1))
                if m := TRAIN.search(line):
                    it, loss, speed, mem = int(m[1]), float(m[2]), float(m[3]), m[4]
                    first_loss = first_loss or loss
                    eta = fmt_eta((total - it) / speed) if speed > 0 else "?"
                    print(f"{time.strftime('%H:%M:%S')}  {bar(it, total)} {it:>5}/{total}  "
                          f"loss {loss:.3f}  {speed:.2f} it/s  ~{eta} left  mem {mem} GB", flush=True)
                elif m := VAL.search(line):
                    it, val = int(m[1]), float(m[2])
                    note = ""
                    if best_val is not None:
                        note = "  ✅ improved" if val < best_val else "  ⚠️ not improving"
                    best_val = val if best_val is None else min(best_val, val)
                    print(f"{time.strftime('%H:%M:%S')}  🧪 validation loss at step {it}: {val:.3f}{note}", flush=True)
                elif "Saved final" in line or "Saved adapter" in line:
                    print(f"\n✅ {line.strip()}\n   Training finished.", flush=True)
                elif "Traceback" in line or "Error" in line:
                    print(f"❌ {line.strip()}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
