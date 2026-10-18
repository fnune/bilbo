const table = document.querySelector("table.list");
const filter = document.querySelector("input.filter");

if (table && filter) {
  const body = table.tBodies[0];
  const rows = [...body.rows];

  filter.addEventListener("input", () => {
    const words = filter.value.toLowerCase().split(/\s+/).filter(Boolean);
    for (const row of rows) {
      row.hidden = !words.every((word) => row.dataset.search.includes(word));
    }
  });

  const cellValue = (row, column) => {
    const cell = row.cells[column];
    return column === 0 ? cell.textContent : JSON.parse(cell.dataset.value);
  };

  const isMissing = (value) => value === "";
  const compareKnown = (a, b) =>
    typeof a === "number" && typeof b === "number" ? a - b : String(a).localeCompare(String(b));

  for (const header of table.querySelectorAll("th[data-sort]")) {
    header.addEventListener("click", () => {
      const column = Number(header.dataset.sort);
      const descending = header.getAttribute("aria-sort") === "ascending";
      for (const other of table.querySelectorAll("th")) other.removeAttribute("aria-sort");
      header.setAttribute("aria-sort", descending ? "descending" : "ascending");
      const sign = descending ? -1 : 1;
      rows.sort((a, b) => {
        const x = cellValue(a, column);
        const y = cellValue(b, column);
        if (isMissing(x) || isMissing(y)) return isMissing(x) - isMissing(y);
        return sign * compareKnown(x, y);
      });
      body.append(...rows);
    });
  }
}
