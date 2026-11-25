// Where the site lives. Once it's on Hindra, change the default to https://macsync.hindra.studio/ too,
// so the copy on GitHub Pages tells search engines that Hindra's is the original.
export const siteUrl = (process.env.SITE_URL ?? "https://onlymoein.github.io/macsync/").replace(/\/*$/, "/");
export const author = { name: "Moein Saharkhiz", url: "https://github.com/onlymoein" };
