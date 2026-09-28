import React, { useState, useMemo } from "react";
import { components, pages } from "./components";
import manifest from "../manifest.json";

type Manifest = {
  components: {
    name: string;
    path: string;
    props: { name: string; type: string }[];
    role?: string;
    states?: string[];
  }[];
  pages: { name: string; path: string }[];
  theme: {
    axes: { name: string; values: string[] }[];
    variables: {
      name: string;
      type: string;
      values: Record<string, unknown>;
    }[];
  };
};

const data = manifest as Manifest;

type View =
  | { kind: "all" }
  | { kind: "component"; name: string }
  | { kind: "page"; name: string }
  | { kind: "variables" };

export default function App() {
  const [view, setView] = useState<View>({ kind: "all" });
  const [search, setSearch] = useState("");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [themeValues, setThemeValues] = useState<Record<string, string>>(() => {
    const initial: Record<string, string> = {};
    for (const axis of data.theme.axes) {
      initial[axis.name] = axis.values[0];
    }
    return initial;
  });

  const filteredComponents = useMemo(
    () =>
      data.components.filter((c) =>
        c.name.toLowerCase().includes(search.toLowerCase())
      ),
    [search]
  );

  const filteredPages = useMemo(
    () =>
      data.pages.filter((p) =>
        p.name.toLowerCase().includes(search.toLowerCase())
      ),
    [search]
  );

  const themeDataAttrs = useMemo(() => {
    const attrs: Record<string, string> = {};
    for (const [key, value] of Object.entries(themeValues)) {
      attrs[`data-${key}`] = value;
    }
    return attrs;
  }, [themeValues]);

  function navigate(v: View) {
    setView(v);
    setSidebarOpen(false);
  }

  const breadcrumb =
    view.kind === "all"
      ? "All Components"
      : view.kind === "component"
        ? view.name
        : view.kind === "page"
          ? view.name
          : "Variables";

  return (
    <div
      className="flex h-screen w-screen overflow-hidden bg-neutral-50 text-neutral-900"
      style={{ fontFamily: "'Inter', system-ui, sans-serif" }}
    >
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-[280px] flex-col border-r border-neutral-800 bg-neutral-900 text-neutral-300 transition-transform lg:static lg:translate-x-0 ${sidebarOpen ? "translate-x-0" : "-translate-x-full"}`}
      >
        <div className="flex h-12 shrink-0 items-center gap-2 border-b border-neutral-800 px-4">
          <div className="h-2 w-2 rounded-full bg-emerald-400" />
          <span className="text-xs font-semibold tracking-wide text-neutral-400 uppercase">
            {{packageName}}
          </span>
        </div>

        <div className="p-3">
          <input
            type="text"
            placeholder="Search…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-md border border-neutral-700 bg-neutral-800 px-3 py-1.5 text-sm text-neutral-200 placeholder-neutral-500 outline-none focus:border-neutral-600 focus:ring-1 focus:ring-neutral-600"
          />
        </div>

        <nav className="flex-1 overflow-y-auto px-2 pb-4">
          <button
            onClick={() => navigate({ kind: "all" })}
            className={`mb-1 w-full rounded-md px-3 py-1.5 text-left text-sm ${view.kind === "all" ? "bg-neutral-800 text-white" : "hover:bg-neutral-800/60"}`}
          >
            Overview
          </button>

          {filteredComponents.length > 0 && (
            <div className="mt-3">
              <div className="px-3 pb-1 text-[10px] font-semibold tracking-widest text-neutral-500 uppercase">
                Components
              </div>
              {filteredComponents.map((c) => (
                <button
                  key={c.name}
                  onClick={() =>
                    navigate({ kind: "component", name: c.name })
                  }
                  className={`w-full rounded-md px-3 py-1.5 text-left text-sm ${view.kind === "component" && view.name === c.name ? "bg-neutral-800 text-white" : "hover:bg-neutral-800/60"}`}
                >
                  {c.name}
                </button>
              ))}
            </div>
          )}

          {filteredPages.length > 0 && (
            <div className="mt-3">
              <div className="px-3 pb-1 text-[10px] font-semibold tracking-widest text-neutral-500 uppercase">
                Pages
              </div>
              {filteredPages.map((p) => (
                <button
                  key={p.name}
                  onClick={() => navigate({ kind: "page", name: p.name })}
                  className={`w-full rounded-md px-3 py-1.5 text-left text-sm ${view.kind === "page" && view.name === p.name ? "bg-neutral-800 text-white" : "hover:bg-neutral-800/60"}`}
                >
                  {p.name}
                </button>
              ))}
            </div>
          )}

          <div className="mt-3">
            <button
              onClick={() => navigate({ kind: "variables" })}
              className={`w-full rounded-md px-3 py-1.5 text-left text-sm ${view.kind === "variables" ? "bg-neutral-800 text-white" : "hover:bg-neutral-800/60"}`}
            >
              Variables
            </button>
          </div>
        </nav>
      </aside>

      {/* Main content */}
      <main className="flex flex-1 flex-col overflow-hidden">
        {/* Header */}
        <header className="flex h-12 shrink-0 items-center justify-between border-b border-neutral-200 bg-white px-4">
          <div className="flex items-center gap-3">
            <button
              className="lg:hidden"
              onClick={() => setSidebarOpen(true)}
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 20 20"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <path d="M3 5h14M3 10h14M3 15h14" />
              </svg>
            </button>
            <span className="text-sm font-medium text-neutral-600">
              {breadcrumb}
            </span>
          </div>

          <div className="flex items-center gap-2">
            {data.theme.axes.map((axis) => (
              <label
                key={axis.name}
                className="flex items-center gap-1.5 text-xs text-neutral-500"
              >
                <span className="capitalize">{axis.name}</span>
                <select
                  value={themeValues[axis.name]}
                  onChange={(e) =>
                    setThemeValues((prev) => ({
                      ...prev,
                      [axis.name]: e.target.value,
                    }))
                  }
                  className="rounded border border-neutral-200 bg-white px-2 py-1 text-xs text-neutral-700 outline-none focus:border-neutral-400"
                >
                  {axis.values.map((v) => (
                    <option key={v} value={v}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
            ))}
          </div>
        </header>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {view.kind === "all" && (
            <AllComponentsView
              packageName="{{packageName}}"
              themeDataAttrs={themeDataAttrs}
            />
          )}
          {view.kind === "component" && (
            <SingleComponentView
              name={view.name}
              themeDataAttrs={themeDataAttrs}
            />
          )}
          {view.kind === "page" && (
            <SinglePageView
              name={view.name}
              themeDataAttrs={themeDataAttrs}
            />
          )}
          {view.kind === "variables" && <VariableView />}
        </div>
      </main>
    </div>
  );
}

function AllComponentsView({
  packageName,
  themeDataAttrs,
}: {
  packageName: string;
  themeDataAttrs: Record<string, string>;
}) {
  return (
    <div>
      <div className="mb-8 rounded-lg border border-neutral-200 bg-white p-6">
        <h1 className="text-lg font-semibold text-neutral-900">
          {packageName}
        </h1>
        <div className="mt-3 space-y-1.5 font-mono text-xs text-neutral-500">
          <p>
            <span className="text-neutral-400">$</span> npm install{" "}
            {packageName}
          </p>
          <p>
            <span className="text-neutral-400">import</span> {"{ Button }"}{" "}
            <span className="text-neutral-400">from</span>{" "}
            <span className="text-emerald-600">"{packageName}"</span>
          </p>
          <p>
            <span className="text-neutral-400">import</span>{" "}
            <span className="text-emerald-600">
              "{packageName}/theme.css"
            </span>
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {data.components.map((c) => {
          const Component = (
            components as Record<string, React.ComponentType>
          )[c.name];
          return (
            <div
              key={c.name}
              className="overflow-hidden rounded-lg border border-neutral-200 bg-white"
            >
              <div className="flex items-center justify-between border-b border-neutral-100 px-4 py-2">
                <span className="text-xs font-medium text-neutral-600">
                  {c.name}
                </span>
              </div>
              <div
                className="flex min-h-[120px] items-center justify-center p-4"
                {...themeDataAttrs}
              >
                {Component ? (
                  <Component />
                ) : (
                  <span className="text-xs text-neutral-400">Not found</span>
                )}
              </div>
            </div>
          );
        })}
        {data.pages.map((p) => {
          const Page = (pages as Record<string, React.ComponentType>)[p.name];
          return (
            <div
              key={p.name}
              className="overflow-hidden rounded-lg border border-neutral-200 bg-white"
            >
              <div className="flex items-center justify-between border-b border-neutral-100 px-4 py-2">
                <span className="text-xs font-medium text-neutral-600">
                  {p.name}
                </span>
                <span className="rounded bg-neutral-100 px-1.5 py-0.5 text-[10px] text-neutral-400">
                  page
                </span>
              </div>
              <div
                className="flex min-h-[120px] items-center justify-center p-4"
                {...themeDataAttrs}
              >
                {Page ? (
                  <Page />
                ) : (
                  <span className="text-xs text-neutral-400">Not found</span>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function SingleComponentView({
  name,
  themeDataAttrs,
}: {
  name: string;
  themeDataAttrs: Record<string, string>;
}) {
  const Component = (components as Record<string, React.ComponentType<Record<string, unknown>>>)[name];
  const meta = data.components.find((c) => c.name === name);

  // Interactive state controls
  const [checked, setChecked] = useState(true);
  const [disabled, setDisabled] = useState(false);
  const [activeStates, setActiveStates] = useState<Set<string>>(new Set());
  const [selected, setSelected] = useState<string>("");

  const isToggle = meta?.role === "toggle";
  const isButton = meta?.role === "button";
  const isLink = meta?.role === "link";
  const isTabBar = meta?.role === "tabBar";
  const hasDisabled = meta?.states?.includes("disabled") ?? false;
  const hasRole = !!meta?.role;

  // Track active pseudo-class states on the preview container
  const handlePointerEnter = () => setActiveStates((s) => new Set(s).add("hover"));
  const handlePointerLeave = () => {
    setActiveStates((s) => { const n = new Set(s); n.delete("hover"); n.delete("pressed"); return n; });
  };
  const handlePointerDown = () => setActiveStates((s) => new Set(s).add("pressed"));
  const handlePointerUp = () => setActiveStates((s) => { const n = new Set(s); n.delete("pressed"); return n; });
  const handleFocus = () => setActiveStates((s) => new Set(s).add("focused"));
  const handleBlur = () => setActiveStates((s) => { const n = new Set(s); n.delete("focused"); return n; });

  // Build props to pass to the component
  const componentProps: Record<string, unknown> = {};
  if (isToggle) {
    componentProps.checked = checked;
    // Drive structural state props from checked — "off" state active when unchecked
    const states = meta?.states ?? [];
    if (states.includes("off")) componentProps.off = !checked;
    if (states.includes("on")) componentProps.on = checked;
  }
  if (hasDisabled) componentProps.disabled = disabled;
  if (isTabBar && selected) componentProps.selected = selected;

  // Click handler for interactive components
  const handlePreviewClick = isToggle
    ? () => setChecked((c) => !c)
    : undefined;

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-neutral-900">{name}</h2>
      {meta && meta.props.length > 0 && (
        <div className="mb-4 rounded-lg border border-neutral-200 bg-white p-4">
          <div className="text-[10px] font-semibold tracking-widest text-neutral-400 uppercase">
            Props
          </div>
          <div className="mt-2 space-y-1">
            {meta.props.map((p) => (
              <div
                key={p.name}
                className="flex items-center gap-2 font-mono text-xs"
              >
                <span className="text-neutral-700">{p.name}</span>
                <span className="text-neutral-400">: {p.type}</span>
              </div>
            ))}
          </div>
        </div>
      )}
      {hasRole && (
        <div className="mb-4 rounded-lg border border-neutral-200 bg-white p-4">
          <div className="text-[10px] font-semibold tracking-widest text-neutral-400 uppercase">
            Interactive State
          </div>
          <div className="mt-3 flex items-center gap-4">
            <span className="rounded bg-neutral-100 px-2 py-0.5 font-mono text-xs text-neutral-700">
              {meta?.role}
            </span>

            {/* Live pseudo-class state indicators */}
            {(isButton || isLink || isToggle) && (
              <div className="flex gap-1.5">
                {(meta?.states ?? [])
                  .filter((s) => ["hover", "pressed", "active", "focused"].includes(s))
                  .map((s) => (
                    <span
                      key={s}
                      className={`rounded-full px-2 py-0.5 text-[10px] font-medium transition-colors ${
                        activeStates.has(s)
                          ? "bg-emerald-100 text-emerald-700"
                          : "bg-neutral-100 text-neutral-400"
                      }`}
                    >
                      {s}
                    </span>
                  ))}
              </div>
            )}
          </div>

          {/* Toggle checked control */}
          {isToggle && (
            <label className="mt-3 flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={checked}
                onChange={(e) => setChecked(e.target.checked)}
                className="h-4 w-4 rounded border-neutral-300 text-neutral-900 focus:ring-neutral-500"
              />
              <span className="text-xs text-neutral-600">
                checked = <span className="font-mono font-medium">{String(checked)}</span>
              </span>
            </label>
          )}

          {/* TabBar selected control */}
          {isTabBar && (meta?.states ?? []).length > 0 && (
            <label className="mt-3 flex items-center gap-2">
              <span className="text-xs text-neutral-600">selected</span>
              <select
                value={selected}
                onChange={(e) => setSelected(e.target.value)}
                className="rounded border border-neutral-200 bg-white px-2 py-1 text-xs font-mono text-neutral-700 outline-none focus:border-neutral-400"
              >
                <option value="">(none)</option>
                {(meta?.states ?? []).map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </label>
          )}

          {/* Disabled control */}
          {hasDisabled && (
            <label className="mt-2 flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={disabled}
                onChange={(e) => setDisabled(e.target.checked)}
                className="h-4 w-4 rounded border-neutral-300 text-neutral-900 focus:ring-neutral-500"
              />
              <span className="text-xs text-neutral-600">
                disabled = <span className="font-mono font-medium">{String(disabled)}</span>
              </span>
            </label>
          )}
        </div>
      )}
      <div className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
        <div className="flex items-center border-b border-neutral-100 px-4 py-2">
          <span className="text-xs font-medium text-neutral-500">Preview</span>
        </div>
        <div
          className={`flex min-h-[200px] items-center justify-center p-8${isToggle ? " cursor-pointer" : ""}`}
          {...themeDataAttrs}
          onClick={handlePreviewClick}
          onPointerEnter={handlePointerEnter}
          onPointerLeave={handlePointerLeave}
          onPointerDown={handlePointerDown}
          onPointerUp={handlePointerUp}
          onFocusCapture={handleFocus}
          onBlurCapture={handleBlur}
        >
          {Component ? (
            <Component {...componentProps} />
          ) : (
            <span className="text-sm text-neutral-400">
              Component not found in registry
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

function SinglePageView({
  name,
  themeDataAttrs,
}: {
  name: string;
  themeDataAttrs: Record<string, string>;
}) {
  const Page = (pages as Record<string, React.ComponentType>)[name];
  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-neutral-900">{name}</h2>
      <div className="overflow-hidden rounded-lg border border-neutral-200 bg-white">
        <div className="flex items-center border-b border-neutral-100 px-4 py-2">
          <span className="text-xs font-medium text-neutral-500">Preview</span>
        </div>
        <div className="p-8" {...themeDataAttrs}>
          {Page ? (
            <Page />
          ) : (
            <span className="text-sm text-neutral-400">
              Page not found in registry
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

function VariableView() {
  const [activeAxis, setActiveAxis] = useState(
    data.theme.axes.length > 0 ? data.theme.axes[0].name : ""
  );

  const grouped = useMemo(() => {
    const colors = data.theme.variables.filter((v) => v.type === "color");
    const numbers = data.theme.variables.filter((v) => v.type === "number");
    const strings = data.theme.variables.filter((v) => v.type === "string");
    return { colors, numbers, strings };
  }, []);

  const axis = data.theme.axes.find((a) => a.name === activeAxis);
  const axisValues = axis?.values ?? ["default"];

  // Build condition keys for each axis value (e.g. "mode:light", "mode:dark")
  const conditionKeys = useMemo(() => {
    return axisValues.map((v) => `${activeAxis}:${v}`);
  }, [activeAxis, axisValues]);

  // Check if a variable has any value for the active axis
  function variableVariesByAxis(variable: (typeof data.theme.variables)[0]) {
    return conditionKeys.some((key) => variable.values[key] !== undefined);
  }

  function renderValue(
    variable: (typeof data.theme.variables)[0],
    conditionKey: string
  ) {
    const val = variable.values[conditionKey];
    if (val === undefined) {
      return <span className="text-neutral-300">—</span>;
    }
    if (variable.type === "color" && typeof val === "string") {
      return (
        <div className="flex items-center gap-2">
          <span
            className="inline-block h-4 w-4 rounded-full border border-neutral-200"
            style={{ backgroundColor: val }}
          />
          <span className="font-mono text-xs">{val}</span>
        </div>
      );
    }
    if (variable.type === "number") {
      return (
        <span className="font-mono text-xs text-neutral-700">
          {String(val)}
        </span>
      );
    }
    return <span className="text-xs text-neutral-700">{String(val)}</span>;
  }

  function renderGroup(
    label: string,
    variables: typeof data.theme.variables
  ) {
    // Only show variables that vary by the selected axis
    const filtered = variables.filter(variableVariesByAxis);
    if (filtered.length === 0) return null;
    return (
      <div className="mb-6">
        <div className="mb-2 text-[10px] font-semibold tracking-widest text-neutral-400 uppercase">
          {label}
        </div>
        <div className="overflow-x-auto rounded-lg border border-neutral-200 bg-white">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-neutral-100 text-left">
                <th className="px-4 py-2 text-xs font-medium text-neutral-500">
                  Name
                </th>
                {axisValues.map((v, i) => (
                  <th
                    key={v}
                    className="px-4 py-2 text-xs font-medium text-neutral-500"
                  >
                    {activeAxis}: {v}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((variable) => (
                <tr
                  key={variable.name}
                  className="border-b border-neutral-50 last:border-0"
                >
                  <td className="px-4 py-2 font-mono text-xs text-neutral-700">
                    {variable.name}
                  </td>
                  {conditionKeys.map((key, i) => (
                    <td key={axisValues[i]} className="px-4 py-2">
                      {renderValue(variable, key)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-neutral-900">Variables</h2>
        {data.theme.axes.length > 1 && (
          <div className="flex gap-1 rounded-md border border-neutral-200 bg-white p-0.5">
            {data.theme.axes.map((a) => (
              <button
                key={a.name}
                onClick={() => setActiveAxis(a.name)}
                className={`rounded px-3 py-1 text-xs font-medium transition-colors ${activeAxis === a.name ? "bg-neutral-900 text-white" : "text-neutral-500 hover:text-neutral-700"}`}
              >
                {a.name}
              </button>
            ))}
          </div>
        )}
      </div>

      {renderGroup("Colors", grouped.colors)}
      {renderGroup("Numbers", grouped.numbers)}
      {renderGroup("Strings", grouped.strings)}
    </div>
  );
}
