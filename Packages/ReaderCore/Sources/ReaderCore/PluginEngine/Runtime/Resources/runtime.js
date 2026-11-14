"use strict";
var BlankGrimoireRuntime = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/index.ts
  var index_exports = {};
  __export(index_exports, {
    UnsupportedApiVersionError: () => UnsupportedApiVersionError,
    __apiVersion: () => __apiVersion,
    __http: () => __http,
    __nativeInvoke: () => __nativeInvoke,
    __parseHTML: () => __parseHTML,
    __timerFire: () => __timerFire,
    assertAdapterAPIVersion: () => assertAdapterAPIVersion,
    clearTimeout: () => clearTimeout,
    console: () => console,
    dispatch: () => dispatch,
    extract: () => extract,
    extractAjax: () => extractAjax,
    extractChapters: () => extractChapters,
    extractCss: () => extractCss,
    extractDetails: () => extractDetails,
    extractHydration: () => extractHydration,
    extractPages: () => extractPages,
    extractScriptJSON: () => extractScriptJSON,
    extractSearch: () => extractSearch,
    normalizeContentRating: () => normalizeContentRating,
    normalizeStatus: () => normalizeStatus,
    parseJSONText: () => parseJSONText,
    readPath: () => readPath,
    resolveSelectors: () => resolveSelectors,
    runStrategy: () => runStrategy,
    setTimeout: () => setTimeout,
    toPages: () => toPages
  });

  // ../types/dist/version.js
  var API_VERSION = 1;

  // src/prelude.ts
  var __apiVersion = API_VERSION;
  function nativeHost() {
    return globalThis.__native;
  }
  var timers = /* @__PURE__ */ new Map();
  var timerHandles = /* @__PURE__ */ new Map();
  var timerIdCounter = 0;
  function setTimeout(cb, ms) {
    const id = ++timerIdCounter;
    timers.set(id, cb);
    const host = nativeHost();
    if (host && typeof host.setTimeout === "function") {
      const handle = host.setTimeout(() => __timerFire(id), ms);
      timerHandles.set(id, handle);
    }
    return id;
  }
  function clearTimeout(id) {
    timers.delete(id);
    const host = nativeHost();
    const handle = timerHandles.get(id);
    if (handle !== void 0 && host && typeof host.clearTimeout === "function") {
      host.clearTimeout(handle);
    }
    timerHandles.delete(id);
  }
  function __timerFire(id) {
    const cb = timers.get(id);
    if (cb) {
      timers.delete(id);
      timerHandles.delete(id);
      cb();
    }
  }
  function __nativeInvoke(fn, ...args) {
    const host = nativeHost();
    if (!host || typeof host[fn] !== "function") {
      throw new Error(`Host function not implemented: ${fn}`);
    }
    return host[fn](...args);
  }
  function __http(request) {
    return new Promise((resolve, reject) => {
      const host = nativeHost();
      if (!host || typeof host.request !== "function") {
        reject(new Error("Host function not implemented: request"));
        return;
      }
      try {
        Promise.resolve(host.request(request)).then(resolve, reject);
      } catch (error) {
        reject(error);
      }
    });
  }
  function __parseHTML(html) {
    const host = nativeHost();
    if (host && typeof host.parseHTML === "function") {
      return host.parseHTML(html);
    }
    const document = globalThis.document;
    if (document?.implementation?.createHTMLDocument) {
      const parsed = document.implementation.createHTMLDocument("");
      if (parsed.documentElement) {
        parsed.documentElement.innerHTML = html;
      }
      return parsed;
    }
    throw new Error("Host function not implemented: parseHTML");
  }
  var console = {
    log: (...args) => {
      nativeHost()?.log?.(...args);
    },
    error: (...args) => {
      nativeHost()?.error?.(...args);
    },
    warn: (...args) => {
      nativeHost()?.warn?.(...args);
    }
  };

  // src/dom.ts
  function queryAll(root, selector) {
    return Array.from(root.querySelectorAll(selector));
  }
  function textOf(element) {
    return (element?.textContent ?? "").trim();
  }
  function attr(element, name) {
    const value = element.getAttribute(name);
    return value !== null && value.trim() !== "" ? value.trim() : null;
  }
  var ABSOLUTE_URL = /^[A-Za-z][A-Za-z0-9+.-]*:/;
  var BASE_URL = /^([A-Za-z][A-Za-z0-9+.-]*:)(\/\/[^/?#]*)?([^?#]*)(\?[^#]*)?(#.*)?$/;
  function normalizePath(path) {
    const segments = [];
    for (const segment of path.split("/")) {
      if (segment === "" || segment === ".") {
        continue;
      }
      if (segment === "..") {
        segments.pop();
        continue;
      }
      segments.push(segment);
    }
    const leading = path.startsWith("/") ? "/" : "";
    const trailing = path.endsWith("/") && segments.length > 0 ? "/" : "";
    return `${leading}${segments.join("/")}${trailing}`;
  }
  function resolveRelativeURL(value, baseURL) {
    if (ABSOLUTE_URL.test(value)) {
      return value;
    }
    if (value.startsWith("//")) {
      const scheme2 = /^[A-Za-z][A-Za-z0-9+.-]*:/.exec(baseURL)?.[0] ?? "";
      return `${scheme2}${value}`;
    }
    const base = BASE_URL.exec(baseURL);
    if (!base) {
      return value;
    }
    const scheme = base[1] ?? "";
    const authority = base[2] ?? "";
    const basePath = base[3] ?? "";
    const baseQuery = base[4] ?? "";
    const hashIndex = value.indexOf("#");
    const hash = hashIndex >= 0 ? value.slice(hashIndex) : "";
    const withoutHash = hashIndex >= 0 ? value.slice(0, hashIndex) : value;
    const queryIndex = withoutHash.indexOf("?");
    const query = queryIndex >= 0 ? withoutHash.slice(queryIndex) : "";
    const path = queryIndex >= 0 ? withoutHash.slice(0, queryIndex) : withoutHash;
    if (path === "") {
      return `${scheme}${authority}${basePath}${query || baseQuery}${hash}`;
    }
    let resolvedPath;
    if (path.startsWith("/")) {
      resolvedPath = normalizePath(path);
    } else {
      const directory = basePath.slice(0, basePath.lastIndexOf("/") + 1) || "/";
      resolvedPath = normalizePath(`${directory}${path}`);
    }
    return `${scheme}${authority}${resolvedPath}${query}${hash}`;
  }
  function resolveURL(value, baseURL) {
    const input = value.trim();
    if (input === "") {
      return baseURL;
    }
    if (typeof URL === "function") {
      try {
        return new URL(input, baseURL).toString();
      } catch {
      }
    }
    return resolveRelativeURL(input, baseURL);
  }
  function firstAttribute(element, names) {
    for (const name of names) {
      const value = attr(element, name);
      if (value) {
        return value;
      }
    }
    return null;
  }

  // src/css.ts
  function extractCss(strategy, document, baseURL) {
    const pages = [];
    for (const element of queryAll(document, strategy.image)) {
      const value = firstAttribute(element, strategy.srcAttributes);
      if (!value) {
        continue;
      }
      const page = {
        index: pages.length,
        imageURL: resolveURL(value, baseURL)
      };
      if (strategy.headers) {
        page.headers = { ...strategy.headers };
      }
      pages.push(page);
    }
    return pages;
  }

  // src/strategies.ts
  var MAX_AJAX_DEPTH = 5;
  function base64Decode(input) {
    try {
      if (typeof atob !== "undefined") {
        return atob(input);
      }
      const buffer = globalThis.Buffer;
      if (buffer) {
        return buffer.from(input, "base64").toString("utf-8");
      }
      throw new Error("no base64 decoder available");
    } catch {
      return input;
    }
  }
  function parseJSONText(text) {
    const trimmed = text.trim();
    try {
      return JSON.parse(trimmed);
    } catch {
    }
    const start = trimmed.search(/[[{]/);
    if (start === -1) {
      return void 0;
    }
    const stack = [];
    let inString = false;
    let escaped = false;
    for (let index = start; index < trimmed.length; index += 1) {
      const character = trimmed[index];
      if (character === void 0) {
        break;
      }
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character === "\\") {
          escaped = true;
        } else if (character === '"') {
          inString = false;
        }
        continue;
      }
      if (character === '"') {
        inString = true;
        continue;
      }
      if (character === "{" || character === "[") {
        stack.push(character);
        continue;
      }
      if (character === "}" || character === "]") {
        const open = stack.pop();
        if (open === void 0 || open === "{" && character !== "}" || open === "[" && character !== "]") {
          return void 0;
        }
        if (stack.length === 0) {
          try {
            return JSON.parse(trimmed.slice(start, index + 1));
          } catch {
            return void 0;
          }
        }
      }
    }
    return void 0;
  }
  function readPath(value, path) {
    if (path.trim() === "") {
      return value;
    }
    let current = value;
    for (const rawPart of path.split(".")) {
      const match = /^([^[\]]*)(?:\[(\d+)\])?$/.exec(rawPart);
      if (!match) {
        return void 0;
      }
      const key = match[1] ?? "";
      if (key !== "") {
        current = current?.[key];
      }
      if (match[2] !== void 0) {
        current = current?.[Number(match[2])];
      }
      if (current === void 0 || current === null) {
        return void 0;
      }
    }
    return current;
  }
  function pageURLFromItem(item) {
    if (typeof item === "string") {
      return item.trim() === "" ? null : item;
    }
    if (item && typeof item === "object") {
      const record = item;
      for (const key of ["imageURL", "url", "src", "image"]) {
        const value = record[key];
        if (typeof value === "string" && value.trim() !== "") {
          return value;
        }
      }
    }
    return null;
  }
  function toPages(payload, baseURL, headers) {
    const candidates = Array.isArray(payload) ? payload : [payload];
    const pages = [];
    for (const candidate of candidates) {
      const value = pageURLFromItem(candidate);
      if (!value) {
        continue;
      }
      const page = {
        index: pages.length,
        imageURL: resolveURL(value, baseURL)
      };
      if (headers) {
        page.headers = { ...headers };
      }
      pages.push(page);
    }
    return pages;
  }
  async function extractScriptJSON(strategy, document, baseURL, parseHTML) {
    const regex = new RegExp(strategy.pattern);
    for (const script of queryAll(document, "script")) {
      const text = textOf(script);
      const src = attr(script, "src");
      let content = "";
      if (text !== "" && regex.test(text)) {
        content = text;
      } else if (src && regex.test(src)) {
        try {
          const response = await __http({ url: resolveURL(src, baseURL), method: "GET" });
          if (response.status < 200 || response.status >= 300) {
            continue;
          }
          content = response.body;
        } catch {
          continue;
        }
      } else {
        continue;
      }
      try {
        const decoded = strategy.base64 ? base64Decode(content) : content;
        const parsed = parseJSONText(decoded);
        if (parsed === void 0) {
          continue;
        }
        const payload = readPath(parsed, strategy.path);
        if (payload === void 0 || payload === null) {
          continue;
        }
        const pages = toPages(payload, baseURL);
        if (pages.length > 0) {
          return pages;
        }
      } catch {
      }
    }
    return [];
  }
  function hydrationPayload(strategy, document, windowObj) {
    if (windowObj) {
      const value = strategy.framework === "next" ? windowObj.__NEXT_DATA__ : windowObj.__NUXT__;
      if (value !== void 0) {
        return value;
      }
    }
    const selectors = strategy.framework === "next" ? ["#__NEXT_DATA__"] : ["#__NUXT_DATA__", "#__NUXT__"];
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      const text = textOf(element);
      if (text !== "") {
        const parsed = parseJSONText(text);
        if (parsed !== void 0) {
          return parsed;
        }
      }
    }
    return void 0;
  }
  function extractHydration(strategy, document, baseURL, windowObj) {
    const payload = hydrationPayload(strategy, document, windowObj);
    if (payload === void 0) {
      return [];
    }
    let value = payload;
    if (strategy.path) {
      value = readPath(payload, strategy.path);
    }
    if (value === void 0 || value === null) {
      return [];
    }
    return toPages(value, baseURL);
  }
  async function extractAjax(strategy, document, environment, depth = 0) {
    if (depth >= MAX_AJAX_DEPTH) {
      return [];
    }
    const url = resolveURL(strategy.path, environment.baseURL);
    const request = {
      url,
      method: strategy.method
    };
    if (strategy.body !== void 0) {
      request.body = strategy.body;
    }
    let response;
    try {
      response = await __http(request);
    } catch {
      return [];
    }
    if (response.status < 200 || response.status >= 300) {
      return [];
    }
    let parsed;
    try {
      parsed = environment.parseHTML ? environment.parseHTML(response.body) : __parseHTML(response.body);
    } catch {
      return [];
    }
    return runStrategy(strategy.then, parsed, environment, depth + 1);
  }
  async function runStrategy(strategy, document, environment, depth = 0) {
    if (!strategy || typeof strategy !== "object") {
      return [];
    }
    const kind = strategy.kind;
    switch (kind) {
      case "css":
        return extractCss(strategy, document, environment.baseURL);
      case "scriptJSON":
        return extractScriptJSON(
          strategy,
          document,
          environment.baseURL,
          environment.parseHTML
        );
      case "hydration":
        return extractHydration(
          strategy,
          document,
          environment.baseURL,
          environment.window
        );
      case "ajax":
        return extractAjax(strategy, document, environment, depth);
      default:
        return [];
    }
  }

  // src/engine.ts
  var UnsupportedApiVersionError = class extends Error {
    constructor(found) {
      super(`Unsupported adapter apiVersion ${String(found)}; expected ${API_VERSION}`);
      this.expected = API_VERSION;
      this.name = "UnsupportedApiVersionError";
      this.found = found;
    }
  };
  function assertAdapterAPIVersion(adapter) {
    if (adapter.apiVersion !== API_VERSION) {
      throw new UnsupportedApiVersionError(adapter.apiVersion);
    }
  }
  function resolveSelectors(base, overrides) {
    const resolved = {
      search: { ...base.search, ...overrides.search },
      details: { ...base.details, ...overrides.details },
      chapters: { ...base.chapters, ...overrides.chapters },
      pages: { strategies: overrides.pages?.strategies ?? base.pages.strategies }
    };
    const attribution = overrides.attribution ? { ...base.attribution, ...overrides.attribution } : base.attribution;
    if (attribution) {
      resolved.attribution = attribution;
    }
    return resolved;
  }
  function selectorsFor(runtime) {
    return resolveSelectors(runtime.adapter.selectors, runtime.context.overrides);
  }
  function readText(root, selector) {
    if (!selector) {
      return void 0;
    }
    const value = textOf(root.querySelector(selector));
    return value === "" ? void 0 : value;
  }
  function readImageURL(root, selector, baseURL) {
    if (!selector) {
      return void 0;
    }
    const element = root.querySelector(selector);
    if (!element) {
      return void 0;
    }
    const image = element.querySelector("img") ?? element;
    const value = firstAttribute(image, ["data-src", "src", "data-original"]);
    return value ? resolveURL(value, baseURL) : void 0;
  }
  function selectLink(element, selector) {
    const descendant = selector ? element.querySelector(selector) : null;
    if (descendant) {
      return descendant;
    }
    return attr(element, "href") ? element : null;
  }
  function splitList(value) {
    if (!value) {
      return void 0;
    }
    const items = value.split(/[,|\n]/).map((item) => item.trim()).filter((item) => item !== "");
    return items.length > 0 ? items : void 0;
  }
  function normalizeStatus(value) {
    const text = value.trim().toLowerCase();
    if (text === "") {
      return "unknown";
    }
    if (/(ongoing|current|publishing|in progress)/.test(text)) {
      return "ongoing";
    }
    if (/(completed|complete|finished|ended)/.test(text)) {
      return "completed";
    }
    if (/(hiatus|on hold|paused)/.test(text)) {
      return "hiatus";
    }
    if (/(cancelled|canceled|dropped|axed)/.test(text)) {
      return "cancelled";
    }
    return "unknown";
  }
  function normalizeContentRating(value) {
    const text = value.trim().toLowerCase();
    if (text === "") {
      return "unknown";
    }
    if (/(safe|all ages|general)/.test(text)) {
      return "safe";
    }
    if (/(suggestive|teen|mature teen)/.test(text)) {
      return "suggestive";
    }
    if (/(mature|adult|explicit|18\+)/.test(text)) {
      return "mature";
    }
    return "unknown";
  }
  function parseChapterNumber(value) {
    if (!value) {
      return void 0;
    }
    const match = /(\d+(?:\.\d+)?)/.exec(value);
    if (!match || match[1] === void 0) {
      return void 0;
    }
    const number = Number(match[1]);
    return Number.isFinite(number) ? number : void 0;
  }
  async function extractSearch(runtime, query) {
    assertAdapterAPIVersion(runtime.adapter);
    const hook = runtime.adapter.hooks?.search;
    if (hook) {
      return hook(runtime.context, query);
    }
    const selectors = selectorsFor(runtime).search;
    const items = [];
    for (const element of queryAll(runtime.document, selectors.item)) {
      const link = selectLink(element, selectors.link);
      const href = link ? attr(link, "href") : null;
      const title = textOf(element.querySelector(selectors.title)) || (link ? textOf(link) : "");
      if (title === "" || !href) {
        continue;
      }
      const summary = {
        key: resolveURL(href, runtime.context.baseURL),
        title
      };
      const cover = readImageURL(element, selectors.cover, runtime.context.baseURL);
      if (cover) {
        summary.coverURL = cover;
      }
      items.push(summary);
    }
    const hasNextPage = selectors.nextPage ? runtime.document.querySelector(selectors.nextPage) !== null : false;
    return { items, hasNextPage };
  }
  async function extractDetails(runtime, key) {
    assertAdapterAPIVersion(runtime.adapter);
    const hook = runtime.adapter.hooks?.getMangaDetails;
    if (hook) {
      return hook(runtime.context, key);
    }
    const selectors = selectorsFor(runtime);
    const detailsSelectors = selectors.details;
    const document = runtime.document;
    const baseURL = runtime.context.baseURL;
    const details = {
      key,
      title: readText(document, detailsSelectors.title) ?? key,
      status: normalizeStatus(readText(document, detailsSelectors.status) ?? ""),
      contentRating: normalizeContentRating(
        readText(document, detailsSelectors.contentRating) ?? ""
      )
    };
    const coverURL = readImageURL(document, detailsSelectors.cover, baseURL);
    if (coverURL) {
      details.coverURL = coverURL;
    }
    const optionalText = [
      ["synopsis", readText(document, detailsSelectors.synopsis)]
    ];
    for (const [field, value] of optionalText) {
      if (value) {
        details[field] = value;
      }
    }
    const altTitles = splitList(readText(document, detailsSelectors.altTitles));
    if (altTitles) {
      details.altTitles = altTitles;
    }
    const authors = splitList(readText(document, detailsSelectors.authors));
    if (authors) {
      details.authors = authors;
    }
    const artists = splitList(readText(document, detailsSelectors.artists));
    if (artists) {
      details.artists = artists;
    }
    const tags = splitList(readText(document, detailsSelectors.tags));
    if (tags) {
      details.tags = tags;
    }
    const attributionSelectors = selectors.attribution;
    const logoURL = readImageURL(document, attributionSelectors?.logo, baseURL);
    const credits = readText(document, attributionSelectors?.credits);
    if (logoURL || credits) {
      const attribution = {
        siteName: runtime.context.siteName,
        siteURL: baseURL
      };
      if (logoURL) {
        attribution.logoURL = logoURL;
      }
      if (credits) {
        attribution.credits = credits;
      }
      details.attribution = attribution;
    }
    return details;
  }
  async function extractChapters(runtime, key) {
    assertAdapterAPIVersion(runtime.adapter);
    const hook = runtime.adapter.hooks?.getChapters;
    if (hook) {
      return hook(runtime.context, key);
    }
    const selectors = selectorsFor(runtime).chapters;
    const baseURL = runtime.context.baseURL;
    const chapters = [];
    for (const element of queryAll(runtime.document, selectors.item)) {
      const link = selectLink(element, selectors.link);
      const href = link ? attr(link, "href") : null;
      if (!href) {
        continue;
      }
      const title = selectors.title ? (readText(element, selectors.title) ?? textOf(link)) || void 0 : textOf(link) || void 0;
      const chapter = { key: resolveURL(href, baseURL) };
      if (title) {
        chapter.title = title;
      }
      const number = parseChapterNumber(title);
      if (number !== void 0) {
        chapter.number = number;
      }
      const dateText = readText(element, selectors.date);
      if (dateText) {
        const time = Date.parse(dateText);
        if (!Number.isNaN(time)) {
          chapter.publishedAt = new Date(time).toISOString();
        }
      }
      chapters.push(chapter);
    }
    const numeric = chapters.every((chapter) => chapter.number !== void 0);
    if (numeric) {
      chapters.sort((a, b) => {
        const left = a.number ?? 0;
        const right = b.number ?? 0;
        return selectors.order === "asc" ? left - right : right - left;
      });
    } else if (selectors.order === "asc") {
      chapters.reverse();
    }
    return chapters;
  }
  async function extractPages(runtime, keys) {
    assertAdapterAPIVersion(runtime.adapter);
    const hook = runtime.adapter.hooks?.getPages;
    if (hook) {
      return hook(runtime.context, keys.mangaKey, keys.chapterKey);
    }
    const selectors = selectorsFor(runtime);
    const environment = { baseURL: runtime.context.baseURL };
    if (runtime.window) {
      environment.window = runtime.window;
    }
    if (runtime.parseHTML) {
      environment.parseHTML = runtime.parseHTML;
    }
    for (const strategy of selectors.pages.strategies) {
      const pages = await runStrategy(strategy, runtime.document, environment);
      if (pages.length > 0) {
        return pages;
      }
    }
    return [];
  }
  async function extractGenres(runtime, mapping) {
    assertAdapterAPIVersion(runtime.adapter);
    const document = runtime.document;
    const filters = [];
    if (!mapping.source) {
      return { filters };
    }
    const elements = document.querySelectorAll(mapping.source);
    for (const element of Array.from(elements)) {
      const displayName = mapping.displayNameAttr ? element.querySelector(mapping.displayNameAttr)?.textContent?.trim() || element.textContent?.trim() : element.textContent?.trim();
      if (!displayName) continue;
      let value = "";
      if (mapping.valueAttr) {
        value = element.getAttribute(mapping.valueAttr) || "";
      } else {
        value = element.textContent?.trim() || "";
      }
      if (mapping.valuePattern) {
        const regex = new RegExp(mapping.valuePattern);
        const match = value.match(regex);
        if (match && match[1]) {
          value = match[1];
        }
      }
      if (value) {
        const href = element.getAttribute("href");
        if (href) {
          filters.push({
            displayName: displayName.trim(),
            value: value.trim(),
            url: href
          });
        } else {
          filters.push({
            displayName: displayName.trim(),
            value: value.trim()
          });
        }
      }
    }
    return { filters };
  }
  var extract = extractPages;
  function asRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
  }
  function toJSON(value) {
    return JSON.stringify(value) ?? "null";
  }
  async function dispatch(runtime, method, argsJSON) {
    assertAdapterAPIVersion(runtime.adapter);
    const args = asRecord(argsJSON.trim() === "" ? {} : JSON.parse(argsJSON));
    switch (method) {
      case "search": {
        const filters = asRecord(args.filters);
        const filterRecord = {};
        for (const [name, value] of Object.entries(filters)) {
          filterRecord[name] = String(value);
        }
        const query = {
          page: typeof args.page === "number" ? args.page : 1
        };
        if (typeof args.text === "string") {
          query.text = args.text;
        }
        if (Object.keys(filterRecord).length > 0) {
          query.filters = filterRecord;
        }
        return toJSON(await extractSearch(runtime, query));
      }
      case "details":
      case "getMangaDetails":
        return toJSON(await extractDetails(runtime, String(args.key ?? "")));
      case "chapters":
      case "getChapters":
        return toJSON(await extractChapters(runtime, String(args.key ?? "")));
      case "pages":
      case "getPages":
        return toJSON(
          await extractPages(runtime, {
            mangaKey: String(args.mangaKey ?? ""),
            chapterKey: String(args.chapterKey ?? "")
          })
        );
      case "extractGenres": {
        const argsRecord = args;
        const mapping = {
          source: String(argsRecord.source ?? "")
        };
        if (argsRecord.displayNameAttr) mapping.displayNameAttr = String(argsRecord.displayNameAttr);
        if (argsRecord.valueAttr) mapping.valueAttr = String(argsRecord.valueAttr);
        if (argsRecord.valuePattern) mapping.valuePattern = String(argsRecord.valuePattern);
        if (argsRecord.filterParam) mapping.filterParam = String(argsRecord.filterParam);
        return toJSON(await extractGenres(runtime, mapping));
      }
      default:
        throw new Error(`Unknown adapter method: ${method}`);
    }
  }
  return __toCommonJS(index_exports);
})();
