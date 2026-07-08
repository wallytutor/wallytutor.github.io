// common.typ
#import ".calepin/calepin.typ" as calepin

#let setup(page-title: "", doc) = {
  calepin.setup(echo: true, results: "verbatim")

  set page(
    paper: "a4",
    header: align(right + horizon, page-title),
    columns: 1,
    numbering: "1",
  )

  set text(font: "Segoe UI", size: 11pt)

  set par(justify: true)

  title[#page-title]

  doc
}

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

#let to-int(val) = {
  if type(val) == int {
    val
  } else if type(val) == str {
    int(val)
  } else if type(val) == content {
    if val.has("text") {
      int(val.text)
    } else if val.has("body") {
      to-int(val.body)
    } else {
      1
    }
  } else {
    1
  }
}

#let get-vars(d) = {
  if type(d) == array {
    let vars = ()
    for item in d {
      vars = vars + get-vars(item)
    }
    vars
  } else if type(d) == content {
    if repr(d.func()) == "space" {
      ()
    } else if d.has("body") {
      get-vars(d.body)
    } else if d.has("children") {
      let vars = ()
      for child in d.children {
        vars = vars + get-vars(child)
      }
      vars
    } else if d.has("text") and d.text in ("(", ")", ",", "[", "]", "{", "}") {
      ()
    } else {
      (d,)
    }
  } else {
    (d,)
  }
}

#let pdiff(num, den, order: none) = {
  let vars = get-vars(den)

  let total-order = if (order != none) {
    to-int(order)
  } else {
    vars.len()
  }

  let top = if total-order > 1 {
    $partial^#total-order #num$
  } else {
    $partial #num$
  }

  let bottom = if vars.len() == 1 {
    let v = vars.at(0)
    if total-order > 1 {
      $partial #v^#total-order$
    } else {
      $partial #v$
    }
  } else {
    vars.map(v => $partial #v$).join(" ")
  }

  $frac(#top, #bottom)$
}

#let sfrac(num, den) = {
  $frac(num, den, style: "horizontal")$
}

// ---------------------------------------------------------------------------
// EOF
// ---------------------------------------------------------------------------
