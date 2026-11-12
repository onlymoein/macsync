import { hydrateRoot, createRoot } from "react-dom/client";
import "@onlymoein/liquidglass/styles.css";
import "./styles.css";
import App from "./App.jsx";

const root = document.getElementById("root");
if (root.firstElementChild) hydrateRoot(root, <App />);
else createRoot(root).render(<App />);
