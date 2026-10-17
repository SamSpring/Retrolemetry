"use strict";
const themeToggle = document.querySelector("#theme-toggle");
const themeLabel = document.querySelector("#theme-label");
function applyTheme(theme) {
  const isPhosphor = theme === "phosphor";
  document.documentElement.dataset.theme = isPhosphor ? "phosphor" : "synthwave";
  themeLabel.textContent = isPhosphor ? "Synthwave" : "Phosphor Green";
  themeToggle.setAttribute("aria-label", `Switch to ${themeLabel.textContent} theme`);
  document.querySelector('meta[name="theme-color"]').content = isPhosphor ? "#020a04" : "#020707";
  for (const image of document.querySelectorAll(".app-preview")) {
    const source = isPhosphor ? image.dataset.phosphorSrc : image.dataset.synthwaveSrc;
    if (source && image.getAttribute("src") !== source) image.src = source;
    image.alt = `${image.dataset.alt} in ${isPhosphor ? "phosphor green" : "cyan and magenta"}.`;
  }
}
if (themeToggle && themeLabel) {
  applyTheme(document.documentElement.dataset.theme);
  themeToggle.hidden = false;
  themeToggle.addEventListener("click", () => {
    const theme = document.documentElement.dataset.theme === "phosphor" ? "synthwave" : "phosphor";
    applyTheme(theme);
    try { localStorage.setItem("retrolemetry.siteTheme", theme); } catch (_) {}
  });
}

const statusLine = document.querySelector("#release-status");
const download = document.querySelector("#download");
fetch("release.json").then(response => {
  if (!response.ok) throw new Error("Release configuration unavailable");
  return response.json();
}).then(release => {
  const repoOK = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(release.repositoryUrl || "");
  const expected = `${release.repositoryUrl}/releases/download/v${release.version}/Retrolemetry-${release.version}.zip`;
  if (repoOK && /^\d+\.\d+\.\d+$/.test(release.version || "") && release.downloadUrl === expected && release.notarized === true && release.publicDownloadVerified === true && release.architecture === "universal" && release.minimumMacOS === "14.0" && /^[a-f0-9]{64}$/.test(release.sha256 || "")) {
    download.href = release.downloadUrl;
    download.textContent = "Download for Mac";
    statusLine.textContent = `Retrolemetry ${release.version} · Developer ID signed and notarized. `;
    const checksum = document.createElement("a");
    checksum.href = `${release.repositoryUrl}/releases/download/v${release.version}/SHA256SUMS.txt`;
    checksum.textContent = "Verify download";
    statusLine.append(checksum);
  }
}).catch(() => {
  // Keep the source link and preparation notice if metadata cannot be verified.
});
