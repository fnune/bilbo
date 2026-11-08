const forgejo = "https://git.fnune.com";
const owner = "fnune";

function forgejoPath({ pathname, searchParams }) {
  const [repo, page, ...rest] = pathname.split("/").filter(Boolean);
  if (!repo) return "/";
  const base = `/${owner}/${repo}`;
  const branch = searchParams.get("h");
  const id = searchParams.get("id");
  switch (page) {
    case "tree":
    case "plain":
      return branch ? `${base}/src/branch/${branch}/${rest.join("/")}` : base;
    case "commit":
      return id ? `${base}/commit/${id}` : base;
    case "log":
      return branch ? `${base}/commits/branch/${branch}` : base;
    default:
      return base;
  }
}

function showLink() {
  const link = document.createElement("a");
  link.href = forgejo + forgejoPath(new URL(location.href));
  link.textContent = "Open in Forgejo";
  link.style.cssText = "position:fixed;top:0.5rem;right:0.5rem;padding:0.25rem 0.5rem;background:#fff;border:1px solid #ccc;border-radius:4px;";
  document.body.append(link);
}

const vpnOnlyProbe = new Image();
vpnOnlyProbe.onload = showLink;
vpnOnlyProbe.src = `${forgejo}/assets/img/favicon.svg?${Date.now()}`;
