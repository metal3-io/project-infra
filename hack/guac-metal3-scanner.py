#!/usr/bin/env python3
"""
Metal3 Multi-Repository Vulnerability Scanner using GUAC
    
WORKFLOW:
  1. Detect versions: Read git tags from 5 Meta3 Go repos
  2. Generate SBOMs: Use Syft to create SPDX-format dependency lists
  3. Ingest to GUAC: Load SBOMs into GUAC database via guacone
  4. Query vulns: Fetch vulnerability records from GUAC GraphQL
  5. Enrich data: Query NVD/OSV APIs for CVSS scores and metadata
     (GUAC's certifier pods crash, so enrichment is done externally)
  6. Filter & classify: Remove false positives, prioritize by severity
  7. Report: Generate consolidated + per-repo JSON reports

CACHE CLEANUP:
  Remove nvd_cache.json to force fresh NVD/OSV queries
  Remove metal3-*.spdx.json files to regenerate SBOMs
  Remove guac-reports/ to clear old reports
"""

import json, subprocess, time, sys, requests, os, signal
from typing import List, Dict, Tuple, Set
from pathlib import Path
from collections import defaultdict
import re

class GuacMetal3Scanner:
    def __init__(self):
        self.guac_url = "http://localhost:8080/query"
        self.repos = {
            "baremetal-operator": "./repos/baremetal-operator",
            "cluster-api-provider-metal3": "./repos/cluster-api-provider-metal3",
            "ip-address-manager": "./repos/ip-address-manager",
            "ironic-standalone-operator": "./repos/ironic-standalone-operator",
            "ironic-ipa-downloader": "./repos/ironic-ipa-downloader"
        }
        self.pids, self.nvd_cache = [], {}
        self.sbom_packages = defaultdict(set)
        self.repo_versions = {}
        self.pkg_purls = {}
        self.visualizer_uris = {}
        self.reports_dir = Path("./guac-reports")
        self.reports_dir.mkdir(parents=True, exist_ok=True)

    def setup_port_forwards(self):
        print("\n Starting port forwards...")
        try:
            self.pids = [subprocess.Popen(["kubectl", "port-forward", "-n", "guac",
                f"svc/{s}", f"{p}:{p}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE).pid
                for s, p in [("graphql-server", "8080"), ("visualizer", "3000")]]
            time.sleep(2)
            for _ in range(5):
                try:
                    requests.get(self.guac_url.replace("/query", "/health"), timeout=2)
                    print(" GUAC API ready\n")
                    return True
                except:
                    time.sleep(1)
        except Exception as e:
            print(f" ERROR: Port forward failed: {e}")
        return False

    def cleanup(self):
        for pid in self.pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except:
                pass

    def get_repo_version(self, repo_name: str, repo_path: str) -> str:
        try:
            result = subprocess.run(
                ["git", "-C", repo_path, "tag", "-l"],
                capture_output=True, text=True, timeout=10
            )
            tags = result.stdout.strip().split('\n')
            semver_tags = [t for t in tags if re.match(r'^v\d+\.\d+\.\d+$', t)]
            if semver_tags:
                latest = sorted(semver_tags, key=lambda x: tuple(map(int, x[1:].split('.'))))[-1]
                return latest[1:]
        except Exception as e:
            print(f" ERROR: Could not detect version for {repo_name}: {e}")
        return "unknown"

    def detect_package_type(self, repo_path: str) -> Tuple[str, str]:
        if Path(f"{repo_path}/go.mod").exists():
            try:
                with open(f"{repo_path}/go.mod") as f:
                    for line in f:
                        if line.startswith("module "):
                            return "golang", line.replace("module ", "").strip()
            except:
                pass
            return "golang", None
        if Path(f"{repo_path}/requirements.txt").exists():
            return "python", None
        if Path(f"{repo_path}/Dockerfile").exists():
            return "dockerfile", None
        return "unknown", None

    def generate_sbom(self, repo_path: str, repo_name: str, version: str) -> str:
        sbom_file = f"{repo_name}-{version}.spdx.json"
        try:
            subprocess.run(["syft", f"dir:{repo_path}", "-o", "spdx-json"],
                stdout=open(sbom_file, 'w'), stderr=subprocess.PIPE, check=True, timeout=60)
            with open(sbom_file) as f:
                sbom = json.load(f)
            for pkg in sbom.get('packages', []):
                self.sbom_packages[repo_name].add(pkg.get('name', '').lower())
            return sbom_file
        except Exception as e:
            print(f"ERROR: Syft failed for {repo_name}: {e}")
            return None

    def patch_sbom_purl(self, sbom_file: str, repo_name: str, version: str, pkg_type: str, module: str) -> bool:
        try:
            with open(sbom_file) as f:
                sbom = json.load(f)
            if 'metadata' not in sbom:
                sbom['metadata'] = {}
            if 'component' not in sbom['metadata']:
                sbom['metadata']['component'] = {}
            purl = f"pkg:golang/{module}@{version}" if pkg_type == "golang" and module else f"pkg:github/metal3-io/{repo_name}@{version}"
            sbom['metadata']['component'].update({
                'purl': purl, 'version': version, 'name': repo_name,
                'type': 'library' if pkg_type == "golang" else 'application'
            })
            with open(sbom_file, 'w') as f:
                json.dump(sbom, f, indent=2)
            return True
        except Exception as e:
            print(f" ERROR: SBOM patching failed for {repo_name}: {e}")
            return False

    def ingest_sbom(self, sbom_file: str, repo_name: str) -> bool:
        try:
            subprocess.run(["guacone", "collect", "--gql-addr", self.guac_url,
                "--add-vuln-on-ingest", "--add-eol-on-ingest", "--add-license-on-ingest",
                "files", sbom_file], capture_output=True, text=True, check=True, timeout=60)
            print(f"-> Ingested {sbom_file}")
            return True
        except Exception as e:
            print(f"ERROR: Ingestion failed for {repo_name}: {str(e)[:80]}")
            return False

    def enrich_with_nvd(self, cve_id: str) -> Dict:
        """
        Enrichment via NVD/OSV APIs (GUAC certifiers are broken).

        NVD: Query for standard CVE-YYYY-XXXXX IDs to get CVSS scores
        OSV: Query for Go/GHSA/PyPI advisories not in NVD

        Rate limits: NVD = 120 req/min, OSV = unlimited
        """
        if not cve_id or cve_id in self.nvd_cache:
            return self.nvd_cache.get(cve_id, {'severity': 'UNKNOWN', 'score': None, 'source': 'none'})

        # Try NVD for standard CVEs
        if cve_id.startswith('CVE-'):
            try:
                r = requests.get(f"https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch={cve_id}", timeout=5)
                if r.status_code == 200:
                    vulns = r.json().get('vulnerabilities', [])
                    if vulns:
                        m = vulns[0].get('cve', {}).get('metrics', {})
                        for k in ['cvssMetricV31', 'cvssMetricV30', 'cvssMetricV2']:
                            c = m.get(k, [{}])[0].get('cvssData', {})
                            if c:
                                res = {'severity': c.get('baseSeverity', 'UNKNOWN'), 'score': c.get('baseScore'), 'source': 'NVD'}
                                self.nvd_cache[cve_id] = res
                                return res
            except:
                pass
            time.sleep(0.5)

        # Try OSV for Go/GHSA/PyPI advisories
        try:
            r = requests.post("https://api.osv.dev/v1/query", json={"query": cve_id}, timeout=5)
            if r.status_code == 200:
                vulns = r.json().get('vulns', [])
                if vulns:
                    v = vulns[0]
                    res = {'severity': v.get('severity', 'UNKNOWN'), 'score': None, 'source': 'OSV'}
                    self.nvd_cache[cve_id] = res
                    return res
        except:
            pass

        time.sleep(0.2)
        res = {'severity': 'UNKNOWN', 'score': None, 'source': 'none'}
        if cve_id.startswith('go-'):
            res['severity'] = 'HIGH'
        elif cve_id.startswith(('ghsa-', 'pysec-')):
            res['severity'] = 'MEDIUM'
        self.nvd_cache[cve_id] = res
        return res

    def get_visualizer_uri(self, purl: str, repo_name: str) -> str:
        try:
            result = subprocess.run(
                ["guacone", "query", "vuln", "uri", purl],
                capture_output=True, text=True, timeout=30
            )
            match = re.search(r'(http://localhost:3000/\?path=[\w,]+)', result.stdout + result.stderr)
            if match:
                return match.group(1)
        except Exception as e:
            print(f"ERROR: Could not get visualizer URI for {repo_name}: {str(e)[:60]}")
        return ""

    def query_guac_all_vulns(self) -> List[Dict]:
        q = {"query": """{
          CertifyVulnList(certifyVulnSpec: {}) {
            edges {
              node {
                package { namespaces { namespace names { id name versions { id version qualifiers { key value } } } } }
                vulnerability { id vulnerabilityIDs { id vulnerabilityID } }
              }
            }
          }
        }"""}
        try:
            r = requests.post(self.guac_url, json=q, timeout=60)
            if r.status_code == 200:
                data = r.json()
                if 'errors' in data:
                    print(f"GraphQL errors: {data['errors']}")
                    return []
                return data.get('data', {}).get('CertifyVulnList', {}).get('edges', [])
        except Exception as e:
            print(f"ERROR: GUAC query failed: {e}")
        return []

    def process_vulns(self, vuln_edges: List[Dict]) -> Tuple[List[Dict], List[Dict]]:
        actionable, filtered = [], []
        seen = set()
        distro = ['tzdata', 'perl', 'util-linux', 'gzip', 'openssl', 'bash', 'curl', 'wget', 'coreutils', 'tar']
        dev_patterns = ['test', '-dev', 'pytest', 'mock', 'junit', 'dev-', '@types/', '-tools', 'sphinx']

        for edge in vuln_edges:
            node = edge.get('node', {})
            vuln_ids = node.get('vulnerability', {}).get('vulnerabilityIDs', [])
            if not vuln_ids:
                continue
            cve_id = vuln_ids[0].get('vulnerabilityID', '')
            pkg_data = node.get('package', {}).get('namespaces', [])
            if not pkg_data:
                filtered.append({'cve': cve_id, 'package': 'unknown', 'reason': 'No package namespace'})
                continue
            names = pkg_data[0].get('names', [])
            if not names:
                filtered.append({'cve': cve_id, 'package': 'unknown', 'reason': 'No package name'})
                continue
            pkg_name, pkg_version = names[0].get('name', '').lower(), names[0].get('versions', [{}])[0].get('version', 'unknown')
            key = (cve_id, pkg_name, pkg_version)
            if key in seen:
                continue
            seen.add(key)
            if any(p in pkg_name for p in dev_patterns):
                filtered.append({'cve': cve_id, 'package': pkg_name, 'version': pkg_version, 'reason': 'Dev-only'})
                continue
            if any(pkg_name.startswith(d) for d in distro):
                filtered.append({'cve': cve_id, 'package': pkg_name, 'version': pkg_version, 'reason': 'Distro (auto-updated)'})
                continue
            nvd_data = self.enrich_with_nvd(cve_id)
            actionable.append({
                'cve': cve_id, 'package': pkg_name, 'version': pkg_version,
                'severity': nvd_data.get('severity'), 'score': nvd_data.get('score'),
                'source': nvd_data.get('source'), 'is_go': cve_id.startswith('go-'),
                'is_ghsa': cve_id.startswith('ghsa-')
            })
        return actionable, filtered

    def scan(self):
        if not self.setup_port_forwards():
            self.cleanup()
            return

        print(f" Scanning {len(self.repos)} Metal3 repos...\n")

        for repo_name, repo_path in self.repos.items():
            if not Path(repo_path).exists():
                print(f"N/A: {repo_name} (not found)")
                continue
            print(f"=== {repo_name}... ===")
            version = self.get_repo_version(repo_name, repo_path)
            self.repo_versions[repo_name] = version
            pkg_type, module = self.detect_package_type(repo_path)
            sbom = self.generate_sbom(repo_path, repo_name, version)
            if not sbom or not self.patch_sbom_purl(sbom, repo_name, version, pkg_type, module):
                continue
            purl = f"pkg:golang/{module}@{version}" if pkg_type == "golang" and module else f"pkg:github/metal3-io/{repo_name}@{version}"
            self.pkg_purls[repo_name] = purl
            if not self.ingest_sbom(sbom, repo_name):
                continue
            if os.path.exists(sbom):
                os.remove(sbom)

        print("\n Waiting for GUAC to process ingestions...\n")
        time.sleep(3)
        print("-> Querying visualizer URLs...")
        for repo_name, purl in self.pkg_purls.items():
            viz_uri = self.get_visualizer_uri(purl, repo_name)
            if viz_uri:
                self.visualizer_uris[repo_name] = viz_uri
        print("-> Querying GUAC for vulnerabilities...\n")

        vulns = self.query_guac_all_vulns()
        if not vulns:
            print("ERROR: No vulnerabilities found in GUAC")
            self.cleanup()
            return

        print(f" Found {len(vulns)} vulnerability records\n")
        actionable, filtered = self.process_vulns(vulns)

        by_repo = defaultdict(list)
        for v in actionable:
            for repo in self.repos.keys():
                if v['package'].lower() == repo.lower() or v['package'].lower() in repo.lower():
                    by_repo[repo].append(v)
                    break
            else:
                by_repo['other'].append(v)

        self.report(by_repo, actionable, filtered)
        self.cleanup()

    def report(self, by_repo: Dict, all_actionable: List[Dict], all_filtered: List[Dict]):
        consolidated = {
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'repos_scanned': len(self.repos),
            'total_vulns': len(all_actionable),
            'total_filtered': len(all_filtered),
            'by_repo': dict(by_repo),
            'all_actionable': all_actionable
        }
        consolidated_path = self.reports_dir / 'metal3-guac-vulns-consolidated.json'
        with open(consolidated_path, 'w') as f:
            json.dump(consolidated, f, indent=2)

        for repo in by_repo.keys():
            if repo == 'other':
                continue
            version = self.repo_versions.get(repo, 'unknown')
            report = {'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'), 'repository': repo,
                      'version': version, 'total_vulns': len(by_repo[repo]), 'vulnerabilities': by_repo[repo]}
            filename = self.reports_dir / f"metal3-{repo}-{version}-vulns.json"
            with open(filename, 'w') as f:
                json.dump(report, f, indent=2)

        print(f"\n{'='*50}\n VULNERABILITY REPORT\n{'='*50}")
        print(f"Total: {len(all_actionable)} found | {len(all_filtered)} filtered\n{'='*50}")

        for repo in sorted(by_repo.keys()):
            if repo == 'other':
                continue
            vulns = by_repo[repo]
            version = self.repo_versions.get(repo, 'unknown')

            critical = [v for v in vulns if v.get('score', 0) and v['score'] >= 9.0]
            urgent_go = [v for v in vulns if v.get('is_go') and (not v.get('score') or v['score'] < 9.0)]
            high_ghsa = [v for v in vulns if v.get('is_ghsa') and (not v.get('score') or v['score'] < 9.0)]

            print(f"  {repo.upper()} @ {version}:")

            if critical:
                print(f"    CRITICAL: {len(critical)}")
                for v in critical:
                    print(f"       {v['cve']} - {v['package']}:{v['version']} (CVSS: {v['score']})")

            if urgent_go:
                print(f"    URGENT Go: {len(urgent_go)}")
                for v in urgent_go[:3]:
                    print(f"       {v['cve']} - {v['package']}:{v['version']}")
                if len(urgent_go) > 3:
                    print(f"       ... and {len(urgent_go) - 3} more")

            if high_ghsa:
                print(f"    HIGH GHSA: {len(high_ghsa)}")

            other = len(vulns) - len(critical) - len(urgent_go) - len(high_ghsa)
            if other > 0:
                print(f"    MEDIUM/OTHER: {other}")

        print(f"\n Reports: {self.reports_dir}/\n")
        print(" Visualizer URLs:")
        for repo in sorted(self.repos.keys()):
            if repo in self.visualizer_uris:
                print(f"\n--> {repo}: {self.visualizer_uris[repo]}\n")
        print()

if __name__ == '__main__':
    s = GuacMetal3Scanner()
    try:
        s.scan()
    except KeyboardInterrupt:
        print("\nInterrupted...")
        s.cleanup()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        s.cleanup()