import { APP_NAME, OWNER_NAME } from "../config";

export function Footer() {
  return (
    <footer className="footer">
      <span>© {new Date().getFullYear()} <b>{OWNER_NAME}</b></span>
      <span className="faint">·</span>
      <span className="faint">{APP_NAME} Unified Command Platform</span>
    </footer>
  );
}
