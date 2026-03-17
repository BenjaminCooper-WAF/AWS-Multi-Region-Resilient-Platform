#!/usr/bin/env python3
import boto3
from datetime import datetime, timezone, timedelta

# Reason why Darth Malgus would be pleased with this script.
# Malgus doesn't "check the console"—he demands a battlefield map in one command.

# Reason why this script is relevant to your career.
# On-call engineers automate triage: reduce time-to-context, not just time-to-click.

# How you would talk about this script at an interview.
# "I wrote a CloudWatch alarm triage tool that summarizes alarm states and recent transitions,
#  so responders immediately know what's broken and when it started."

import boto3
from botocore.exceptions import BotoCoreError, ClientError

cw = boto3.client("cloudwatch")

def iter_metric_alarms_in_alarm():
    paginator = cw.get_paginator("describe_alarms")
    pages = paginator.paginate(
        StateValue="ALARM",
        AlarmTypes=["MetricAlarm"],
        PaginationConfig={"PageSize": 100},
    )

    for page in pages:
        for alarm in page.get("MetricAlarms", []):
            yield alarm

def main():
    try:
        alarms = list(iter_metric_alarms_in_alarm())
        print(f"\nActive alarms: {len(alarms)}\n")

        for a in alarms:
            stat = a.get("Statistic") or a.get("ExtendedStatistic") or "-"
            print(f"- {a['AlarmName']}")
            print(f"  Metric: {a.get('Namespace')} {a.get('MetricName')} {stat}")
            print(f"  Reason: {a.get('StateReason', '')[:160]}")
            print(f"  Updated: {a.get('StateUpdatedTimestamp')}")
            print(f"  Actions: {', '.join(a.get('AlarmActions', [])) or '-'}")
            print()
    except (ClientError, BotoCoreError) as e:
        print(f"CloudWatch error: {e}")

if __name__ == "__main__":
    main()