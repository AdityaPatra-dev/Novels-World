#!/usr/bin/env python3
"""
Automated GitHub Issue Reporter for Novels-World.
Checks health report JSON / test results and creates, updates, or resolves
GitHub issues using a Personal Access Token (PAT) or GITHUB_TOKEN.
"""

import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

def make_github_request(url, method='GET', data=None, token=None):
    headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Novels-World-Health-Reporter/1.0',
    }
    if token:
        headers['Authorization'] = f'Bearer {token}'
    
    encoded_data = json.dumps(data).encode('utf-8') if data else None
    req = urllib.request.Request(url, data=encoded_data, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as resp:
            status = resp.status
            body = resp.read().decode('utf-8')
            return status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8')
        print(f"[HTTP {e.code}] {method} {url}: {err_msg}", file=sys.stderr)
        return e.code, {'error': err_msg}
    except Exception as e:
        print(f"[Request Error] {method} {url}: {e}", file=sys.stderr)
        return 0, {'error': str(e)}

def find_open_issue(repo, token):
    url = f"https://api.github.com/repos/{repo}/issues?state=open&labels=source-health&per_page=5"
    status, data = make_github_request(url, 'GET', token=token)
    if status == 200 and isinstance(data, list) and len(data) > 0:
        return data[0]
    return None

def create_issue(repo, token, title, body, labels):
    url = f"https://api.github.com/repos/{repo}/issues"
    payload = {
        'title': title,
        'body': body,
        'labels': labels
    }
    status, data = make_github_request(url, 'POST', data=payload, token=token)
    if status == 201:
        print(f"✅ Successfully created GitHub Issue #{data.get('number')}: {data.get('html_url')}")
        return data
    else:
        print(f"❌ Failed to create GitHub issue: {data}")
        return None

def update_issue_comment(repo, token, issue_number, comment_body):
    url = f"https://api.github.com/repos/{repo}/issues/{issue_number}/comments"
    payload = {'body': comment_body}
    status, data = make_github_request(url, 'POST', data=payload, token=token)
    if status == 201:
        print(f"✅ Appended status update comment to existing Issue #{issue_number}")
        return data
    return None

def close_issue(repo, token, issue_number, closing_comment):
    update_issue_comment(repo, token, issue_number, closing_comment)
    url = f"https://api.github.com/repos/{repo}/issues/{issue_number}"
    payload = {'state': 'closed'}
    status, data = make_github_request(url, 'PATCH', data=payload, token=token)
    if status == 200:
        print(f"🎉 Successfully closed Issue #{issue_number} (all checks passing).")
        return data
    return None

def main():
    dry_run = '--dry-run' in sys.argv
    token = os.environ.get('PAT_TOKEN') or os.environ.get('GITHUB_TOKEN')
    repo = os.environ.get('GITHUB_REPOSITORY') or 'AdityaPatra-dev/Novels-World'
    server_url = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
    run_id = os.environ.get('GITHUB_RUN_ID', '')
    sha = os.environ.get('GITHUB_SHA', '')[:7]
    run_url = f"{server_url}/{repo}/actions/runs/{run_id}" if run_id else "Local Run"

    analysis_status = os.environ.get('STATIC_ANALYSIS_STATUS', 'success')
    tests_status = os.environ.get('TEST_SUITE_STATUS', 'success')
    source_health_status = os.environ.get('SOURCE_HEALTH_STATUS', 'success')

    # Read health report JSON if available
    report_data = {}
    report_file = 'build/reports/source_health_summary.json'
    if os.path.exists(report_file):
        try:
            with open(report_file, 'r', encoding='utf-8') as f:
                report_data = json.load(f)
        except Exception as e:
            print(f"Warning: Could not parse {report_file}: {e}")

    total_sources = report_data.get('total_sources', 0)
    failed_count = report_data.get('failed_count', 0)
    healthy_count = report_data.get('healthy_count', 0)
    health_pct = report_data.get('health_percentage', '100')
    source_results = report_data.get('results', [])
    failed_sources = [s for s in source_results if s.get('status') != 'HEALTHY']

    has_failures = (
        failed_count > 0 or
        analysis_status != 'success' or
        tests_status != 'success' or
        source_health_status != 'success'
    )

    now_str = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')

    print(f"\n==========================================")
    print(f"📊 HEALTH REPORT EVALUATION ({now_str})")
    print(f" - Static Analysis: {analysis_status}")
    print(f" - Unit Tests: {tests_status}")
    print(f" - Source Health Check: {source_health_status}")
    print(f" - Total Sources Tested: {total_sources} (Failed: {failed_count})")
    print(f" - Overall Status: {'❌ FAILURES DETECTED' if has_failures else '✅ ALL PASSING'}")
    print(f"==========================================\n")

    open_issue = find_open_issue(repo, token) if token else None

    if not has_failures:
        if open_issue and token:
            closing_msg = (
                f"### 🎉 Source & Test Health Restored\n\n"
                f"All website sources ({total_sources}/{total_sources}) and automated test suites passed successfully on **{now_str}**.\n\n"
                f"- **Actions Run:** [{run_url}]({run_url})\n"
                f"- **Commit:** `{sha}`\n\n"
                f"Closing this alert issue automatically."
            )
            close_issue(repo, token, open_issue['number'], closing_msg)
        else:
            print("✅ All checks passed and no open alert issue exists. Nothing to do.")
        return 0

    # Build Failure Report Markdown
    title = f"🚨 Daily Health Alert: {failed_count} Source(s) Failed / Checks Failing ({now_str.split(' ')[0]})"
    
    body_lines = [
        f"## 🚨 Automated Daily Health Check Alert",
        f"**Timestamp:** `{now_str}` | **Run:** [{run_url}]({run_url}) | **Commit:** `{sha}`\n",
        f"### 📋 System Health Overview",
        f"| Component | Status |",
        f"| :--- | :--- |",
        f"| **Static Analysis (`flutter analyze`)** | {'✅ PASS' if analysis_status == 'success' else '❌ FAIL'} |",
        f"| **Core Unit Tests (`flutter test`)** | {'✅ PASS' if tests_status == 'success' else '❌ FAIL'} |",
        f"| **Live Sources Catalog** | **{healthy_count}/{total_sources} Operational ({health_pct}%)** |",
        f"| **Failing Sources Count** | **{failed_count} Broken** |",
        "",
    ]

    if failed_sources:
        body_lines.extend([
            f"### ❌ Failing Novel Sources ({len(failed_sources)})",
            f"| Source Name | ID | Lang | Base URL | Error Category | Latency | Error Details |",
            f"| :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
        ])
        for fs in failed_sources:
            clean_err = fs.get('error_message', '').replace('\n', ' ').replace('|', '/')
            if len(clean_err) > 80:
                clean_err = clean_err[:77] + '...'
            body_lines.append(
                f"| **{fs.get('name')}** | `{fs.get('id')}` | `{fs.get('lang')}` | "
                f"[{fs.get('baseUrl')}]({fs.get('baseUrl')}) | "
                f"**{fs.get('error_type')}** | `{fs.get('latency_ms')}ms` | `{clean_err}` |"
            )
        body_lines.append("")

    body_lines.extend([
        f"### 🛠️ Recommended Action Items",
        f"- [ ] Review failing sources against Cloudflare / anti-bot protection changes.",
        f"- [ ] Check whether target domain changed or redirected to a new mirror.",
        f"- [ ] Verify HTML DOM selector changes in extractor class if empty catalog was returned.",
        f"- [ ] Run `flutter test test/sources_health_check_test.dart` locally to reproduce.",
        f"\n---\n*This issue was generated automatically by Novels-World Daily Source Health Workflow.*"
    ])

    issue_body = "\n".join(body_lines)

    if dry_run:
        print("[Dry Run Mode] Issue Title:")
        print("  " + title)
        print("\n[Dry Run Mode] Issue Body:")
        print(issue_body)
        print("\n[Dry Run Mode] No GitHub API calls will be made.")
        return 0

    if not token:
        print("⚠️ Warning: No PAT_TOKEN or GITHUB_TOKEN provided. Cannot create or update GitHub issues.")
        return 1

    if open_issue:
        print(f"Found existing open issue #{open_issue['number']}. Appending update comment...")
        comment_body = (
            f"### 🔄 Health Check Update: {now_str}\n\n"
            f"- **Run:** [{run_url}]({run_url})\n"
            f"- **Failed Sources:** `{failed_count}/{total_sources}`\n"
            f"- **Unit Tests:** `{'PASS' if tests_status == 'success' else 'FAIL'}`\n\n"
            + issue_body
        )
        update_issue_comment(repo, token, open_issue['number'], comment_body)
    else:
        print("Creating new GitHub Issue...")
        labels = ['bug', 'source-health', 'automated-check']
        create_issue(repo, token, title, issue_body, labels)

    return 0

if __name__ == '__main__':
    sys.exit(main())
