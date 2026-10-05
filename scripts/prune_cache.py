#!/usr/bin/env python3
import argparse
import os
import sys

def main():
    parser = argparse.ArgumentParser(description="Prune cache using size-based LRU eviction.")
    parser.add_argument("--cache-dir", required=True, help="Directory to prune (e.g. vcpkg-binary)")
    parser.add_argument("--max-bytes", type=int, default=5368709120, help="Max size in bytes (default 5 GiB)")
    parser.add_argument("--touch-abis", help="Optional file containing active 64-char package ABIs to touch")
    args = parser.parse_args()

    target_dir = os.path.abspath(args.cache_dir)
    if not os.path.isdir(target_dir):
        print(f"Directory {target_dir} does not exist, skipping.")
        return

    # 1. Touch active ABIs if provided
    if args.touch_abis and os.path.isfile(args.touch_abis):
        touched = 0
        with open(args.touch_abis, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if len(line) == 64:
                    pkg_path = os.path.join(target_dir, line[:2], f"{line}.zip")
                    if os.path.isfile(pkg_path):
                        try:
                            os.utime(pkg_path, None)
                            touched += 1
                        except OSError:
                            pass
        print(f"Refreshed mtime for {touched} active packages from {args.touch_abis}")

    # 2. Gather all .zip files and compute size
    files = []
    total_size = 0
    for root, _, filenames in os.walk(target_dir):
        for f in filenames:
            if f.endswith(".zip"):
                p = os.path.join(root, f)
                try:
                    st = os.stat(p)
                    files.append((st.st_mtime, st.st_size, p))
                    total_size += st.st_size
                except OSError:
                    pass

    print(f"Cache {target_dir}: current size {total_size / (1024**3):.2f} GB (max {args.max_bytes / (1024**3):.2f} GB, {len(files)} files)")

    # 3. LRU Eviction: remove oldest files if total size exceeds limit
    if total_size > args.max_bytes:
        files.sort(key=lambda x: x[0])  # oldest first
        deleted_count = 0
        deleted_bytes = 0
        for _, size, p in files:
            if total_size <= args.max_bytes:
                break
            try:
                os.remove(p)
                total_size -= size
                deleted_bytes += size
                deleted_count += 1
            except OSError:
                pass
        print(f"LRU eviction: deleted {deleted_count} files ({deleted_bytes / (1024**3):.2f} GB). New size: {total_size / (1024**3):.2f} GB")

    # 4. Clean empty directories
    for root, dirs, _ in os.walk(target_dir, topdown=False):
        for d in dirs:
            dp = os.path.join(root, d)
            try:
                os.rmdir(dp)
            except OSError:
                pass

if __name__ == "__main__":
    main()
