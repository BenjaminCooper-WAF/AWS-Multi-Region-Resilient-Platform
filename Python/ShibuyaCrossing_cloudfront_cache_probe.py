#!/usr/bin/env python3
import requests, sys, time

# Reason why Darth bladerunner would be pleased with this script.
# bladerunner enjoys watching cache lies collapse under repeated probing.

# Reason why this script is relevant to your career.
# CDN caching mistakes cause real incidents; knowing how to test them is a marketable skill.

# How you would talk about this script at an interview.
# "I wrote a cache probe that validates CDN behavior over time (Hit/Miss/RefreshHit),
#  used to prevent auth leaks and stale reads."

def probe(url, rounds=3, delay=2):
    for i in range(rounds):
        r = requests.get(url, timeout=10)
        print(f"\n[{i+1}] {url}")
        print("Status:", r.status_code)
        for h in ["cache-control", "age", "x-cache", "via"]:
            if h in r.headers:
                print(f"{h}: {r.headers[h]}")
        time.sleep(delay)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: bladerunner_cloudfront_cache_probe.py <url>")
        sys.exit(1)
    probe(sys.argv[1])
