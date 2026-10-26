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
    tts_status = os.environ.get('TTS_HEALTH_STATUS', 'success')

    # Read health report JSON if available
    report_data = {}
    report_file = 'build/reports/source_health_summary.json'
    if os.path.exists(report_file):
        try:
            with open(report_file, 'r', encoding='utf-8') as f:
                report_data = json.load(f)
        except Exception as e:
            print(f"Warning: Could not parse {report_file}: {e}")

    # Read TTS health report JSON if available
    tts_data = {}
    tts_file = 'build/reports/tts_health_summary.json'
    if os.path.exists(tts_file):
        try:
            with open(tts_file, 'r', encoding='utf-8') as f:
                tts_data = json.load(f)
        except Exception as e:
            print(f"Warning: Could not parse {tts_file}: {e}")

    total_sources = report_data.get('total_sources', 0)
    failed_count = report_data.get('failed_count', 0)
    healthy_count = report_data.get('healthy_count', 0)
    health_pct = report_data.get('health_percentage', '100')
    source_results = report_data.get('results', [])
    failed_sources = [s for s in source_results if s.get('status') != 'HEALTHY']

    tts_healthy = (
        tts_status == 'success' and
        tts_data.get('status', 'HEALTHY') != 'FAILED'
    )

    failed_steps = [
        name for name, status in [
            ('Static Analysis', analysis_status),
            ('Unit Tests', tests_status),
            ('Source Health Check', source_health_status),
            ('Neural TTS Live Health', tts_status if tts_healthy else 'failure'),
        ] if status in ('failure', 'timed_out')
    ]
    has_failures = (failed_count > 0 or len(failed_steps) > 0 or not tts_healthy)

    now_str = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')

    print(f"\n==========================================")
    print(f"📊 HEALTH REPORT EVALUATION ({now_str})")
    print(f" - Static Analysis: {analysis_status}")
    print(f" - Unit Tests: {tests_status}")
    print(f" - Source Health Check: {source_health_status}")
    print(f" - Neural TTS Live Health: {'HEALTHY' if tts_healthy else 'FAILED'} ({tts_status})")
    print(f" - Total Sources Tested: {total_sources} (Failed: {failed_count})")
    print(f" - Overall Status: {'❌ FAILURES DETECTED' if has_failures else '✅ ALL PASSING'}")
    print(f"==========================================\n")

    open_issue = find_open_issue(repo, token) if token else None

    if not has_failures:
        if open_issue and token:
            closing_msg = (
                f"### 🎉 Source, TTS & Test Health Restored\n\n"
                f"All website sources ({total_sources}/{total_sources}), neural text-to-speech services, and automated test suites passed successfully on **{now_str}**.\n\n"
                f"- **Actions Run:** [{run_url}]({run_url})\n"
                f"- **Commit:** `{sha}`\n\n"
                f"Closing this alert issue automatically."
            )
            close_issue(repo, token, open_issue['number'], closing_msg)
        else:
            print("✅ All checks passed and no open alert issue exists. Nothing to do.")
        return 0

    # Build Failure Report Markdown
    issue_reasons = []
    if failed_count > 0:
        issue_reasons.append(f"{failed_count} Source(s) Failed")
    if not tts_healthy:
        issue_reasons.append("Neural TTS Failed")
    if tests_status in ('failure', 'timed_out'):
        issue_reasons.append("Unit Tests Failing")
    if analysis_status in ('failure', 'timed_out'):
        issue_reasons.append("Analysis Failing")

    reasons_str = " / ".join(issue_reasons) if issue_reasons else "Checks Failing"
    title = f"🚨 Daily Health Alert: {reasons_str} ({now_str.split(' ')[0]})"
    
    tts_latency_str = f" ({tts_data.get('latency_ms')}ms)" if tts_data.get('latency_ms') else ""
    body_lines = [
        f"## 🚨 Automated Daily Health Check Alert",
        f"**Timestamp:** `{now_str}` | **Run:** [{run_url}]({run_url}) | **Commit:** `{sha}`\n",
        f"### 📋 System Health Overview",
        f"| Component | Status |",
        f"| :--- | :--- |",
        f"| **Static Analysis (`flutter analyze`)** | {'✅ PASS' if analysis_status == 'success' else '❌ FAIL'} |",
        f"| **Core Unit Tests (`flutter test`)** | {'✅ PASS' if tests_status == 'success' else '❌ FAIL'} |",
        f"| **Microsoft Edge Neural TTS** | {'✅ PASS' + tts_latency_str if tts_healthy else '❌ FAIL'} |",
        f"| **Live Sources Catalog** | **{healthy_count}/{total_sources} Operational ({health_pct}%)** |",
        f"| **Failing Sources Count** | **{failed_count} Broken** |",
        "",
    ]

    if not tts_healthy:
        body_lines.extend([
            f"### 🎙️ Microsoft Edge Neural TTS Diagnostic Details",
            f"- **Status:** `{'FAILED' if not tts_healthy else tts_data.get('status', 'HEALTHY')}`",
            f"- **Error Category:** `{tts_data.get('error_type') or 'Synthesis or Handshake Test Failed'}`",
            f"- **Error Message:** `{tts_data.get('error_message') or 'Check workflow test logs for detailed exception'}`",
            f"- **DRM Token Algorithm:** `{'✅ Passed' if tts_data.get('drm_token_valid') else '❌ Failed'}`",
            f"- **WebSocket Connection:** `{'✅ Connected' if tts_data.get('websocket_handshake') else '❌ Failed'}`",
            f"- **MP3 Header Valid:** `{'✅ Valid' if tts_data.get('mp3_header_valid') else '❌ Invalid'}`",
            "",
        ])

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

    action_items = [
        "### 🛠️ Recommended Action Items",
    ]
    if not tts_healthy:
        action_items.extend([
            "- [ ] **[TTS Alert]** Verify Microsoft Edge TTS Sec-MS-GEC v2 algorithm in `lib/tts/services/edge_drm.dart`.",
            "- [ ] **[TTS Alert]** Check browser build version (`2-143.0.3650.75`) in `EdgeDrm.secMsGecVersion`.",
            "- [ ] **[TTS Alert]** Run `flutter test test/tts_live_health_test.dart` locally to examine handshake errors.",
        ])
    if failed_sources:
        action_items.extend([
            "- [ ] Review failing sources against Cloudflare / anti-bot protection changes.",
            "- [ ] Check whether target domain changed or redirected to a new mirror.",
            "- [ ] Verify HTML DOM selector changes in extractor class if empty catalog was returned.",
            "- [ ] Run `flutter test test/sources_health_check_test.dart` locally to reproduce.",
        ])
    if tests_status in ('failure', 'timed_out'):
        action_items.append("- [ ] Run `flutter test` locally to inspect unit test failures.")
    action_items.append("\n---\n*This issue was generated automatically by Novels-World Daily Source Health Workflow.*")

    body_lines.extend(action_items)

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
            f"- **Neural TTS:** `{'PASS' if tts_healthy else 'FAIL'}`\n"
            f"- **Unit Tests:** `{'PASS' if tests_status == 'success' else 'FAIL'}`\n\n"
            + issue_body
        )
        update_issue_comment(repo, token, open_issue['number'], comment_body)
    else:
        print("Creating new GitHub Issue...")
        labels = ['bug', 'source-health', 'automated-check']
        if not tts_healthy:
            labels.append('tts')
        create_issue(repo, token, title, issue_body, labels)

    return 0

if __name__ == '__main__':
    sys.exit(main())
