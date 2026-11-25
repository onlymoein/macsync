import { renderToString } from "react-dom/server";
import App from "./App.jsx";

export const render = () => renderToString(<App />);
export * as content from "./content.js";
