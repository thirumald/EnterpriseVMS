import { APP_NAME, APP_TAGLINE, OWNER_NAME } from "../config";

export function Footer() {
  return (
    <footer className="footer">
      <span>© {new Date().getFullYear()} <b>{OWNER_NAME}</b></span>
      <span className="faint">·</span>
      <span className="faint">{APP_NAME} · {APP_TAGLINE}</span>
    </footer>
  );
}
