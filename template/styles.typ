#let brand-blue = rgb("2b6cb0")
#let brand-dark = rgb("1a365d")
#let brand-grey = rgb("4a5568")
#let brand-light-bg = rgb("f7fafc")
#let brand-border = rgb("e2e8f0")

// ---------------------------------------------------------------------------
// QUARTO SCAFFOLDING & STANDARD DEFINITIONS
//
// These functions and helper blocks are used by Quarto's default Pandoc
// compilation pipeline. They ensure compatibility with standard Quarto blocks.
// ---------------------------------------------------------------------------

#let blockquote(body) = [
  #set text( size: 0.92em )
  #block(inset: (left: 1.5em, top: 0.2em, bottom: 0.2em))[#body]
]

#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#let endnote(num, contents) = [
  #stack(dir: ltr, spacing: 3pt, super[#num], contents)
]

// Custom show rule for term-definition lists (dl in HTML). Formatted as a
// grid where the term key is styled using the level 3 heading blue color.
#show terms: it => {
  grid(
    columns: (auto, 1fr),
    column-gutter: 1.5em,
    row-gutter: 0.8em,
    ..it.children.map(child => (
      text(
        fill: brand-blue,
        weight: "medium"
      )[#child.term],
      child.description
    )).flatten()
  )
}

#show raw.where(block: true): set block(
  fill: luma(230),
  width: 100%,
  inset: 8pt,
  radius: 2pt
)

#let block_with_new_content(old_block, new_content) = {
  let d = (:)
  let fields = old_block.fields()
  fields.remove("body")
  if fields.at("below", default: none) != none {
    fields.below = fields.below.abs
  }
  return block.with(..fields)(new_content)
}

#let empty(v) = {
  if type(v) == str {
    v.matches(regex("^\\s*$$")).at(0, default: none) != none
  } else if type(v) == content {
    if v.at("text", default: none) != none {
      return empty(v.text)
    }
    for child in v.at("children", default: ()) {
      if not empty(child) {
        return false
      }
    }
    return true
  }
}

// Subfloats setup
#let quartosubfloatcounter = counter("quartosubfloatcounter")
#let quarto_super(
  kind: str,
  caption: none,
  label: none,
  supplement: str,
  position: none,
  subrefnumbering: "1a",
  subcapnumbering: "(a)",
  body,
) = {
  context {
    let figcounter = counter(figure.where(kind: kind))
    let n-super = figcounter.get().first() + 1
    set figure.caption(position: position)
    [#figure(
      kind: kind,
      supplement: supplement,
      caption: caption,
      {
        show figure.where(kind: kind): set figure(numbering: _ => numbering(subrefnumbering, n-super, quartosubfloatcounter.get().first() + 1))
        show figure.where(kind: kind): set figure.caption(position: position)

        show figure: it => {
          let num = numbering(subcapnumbering, n-super, quartosubfloatcounter.get().first() + 1)
          show figure.caption: it => {
            num.slice(2)
            [ ]
            it.body
          }

          quartosubfloatcounter.step()
          it
          counter(figure.where(kind: it.kind)).update(n => n - 1)
        }

        quartosubfloatcounter.update(0)
        body
      }
    )#label]
  }
}

// ---------------------------------------------------------------------------
// QUARTO CALLOUT BLOCKS INTEGRATION
// ---------------------------------------------------------------------------

#show figure: it => {
  if type(it.kind) != str {
    return it
  }
  let kind_match = it.kind.matches(regex("^quarto-callout-(.*)")).at(0, default: none)
  if kind_match == none {
    return it
  }
  let kind = kind_match.captures.at(0, default: "other")
  kind = upper(kind.first()) + kind.slice(1)

  let old_callout = it.body.children.at(1).body.children.at(1)
  let old_title_block = old_callout.body.children.at(0)
  let old_title = old_title_block.body.body.children.at(2)

  let new_title = if empty(old_title) {
    [#kind #it.counter.display()]
  } else {
    [#kind #it.counter.display(): #old_title]
  }

  let new_title_block = block_with_new_content(
    old_title_block,
    block_with_new_content(
      old_title_block.body,
      old_title_block.body.body.children.at(0) +
      old_title_block.body.body.children.at(1) +
      new_title))

  block_with_new_content(old_callout,
    block(below: 0pt, new_title_block) +
    old_callout.body.children.at(1))
}

#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false,
    fill: background_color,
    stroke: (paint: icon_color, thickness: 0.5pt, cap: "round"),
    width: 100%,
    radius: 2pt,
    block(
      inset: 1pt,
      width: 100%,
      below: 0pt,
      block(
        fill: background_color,
        width: 100%,
        inset: 8pt)[#text(icon_color, weight: 900)[#icon] #title]) +
      if(body != []){
        block(
          inset: 1pt,
          width: 100%,
          block(fill: body_background_color, width: 100%, inset: 8pt, body))
      }
    )
}

// ---------------------------------------------------------------------------
// CUSTOM GLOBAL ELEMENT STYLING
// ---------------------------------------------------------------------------

#set table(
  inset: 6pt,
  stroke: none
)

#show figure.where(
  kind: table
): set figure.caption(
  position: $if(table-caption-position)$$table-caption-position$$else$top$endif$
)

#show figure.where(
  kind: image
): set figure.caption(
  position: $if(figure-caption-position)$$figure-caption-position$$else$bottom$endif$
)

#import "@preview/fontawesome:0.5.0": *

#let education-entry(body) = block(
  stroke: (left: 2pt + brand-blue),
  inset: (left: 0.75em),
  below: 1.5em,
  body
)

#let experience-entry(body) = block(
  below: 1.5em,
  body
)

#let inline-dl(body) = {
  show terms: it => {
    it.children.map(child => {
      let desc = child.description

      if desc.has("body") {
        desc = desc.body
      }

      [
        #text(fill: brand-blue, weight: "semibold")[#child.term]: #desc
      ]
    }).join(v(0.8em))
  }
  body
}

// ---------------------------------------------------------------------------
// CUSTOM CONFIGURATION & LAYOUT FUNCTION (conf)
//
// The main layout styling function that wraps the entire document. It sets up
// page margins, default fonts, heading colors/strokes, and the title block.
// ---------------------------------------------------------------------------

#let conf(
  title: none,
  subtitle: none,
  personal-info: none,
  authors: (),
  keywords: (),
  date: none,
  lang: "en",
  region: none,
  abstract: none,
  abstract-title: none,
  toc_title: none,
  toc_depth: none,
  margin: (x: 1.0cm, y: 1.0cm),
  paper: "a4",
  font: ("Segoe UI",),
  fontsize: 10pt,
  pagenumbering: none,
  cols: 2,
  doc,
) = {
  // Page settings
  set page(
    paper: paper,
    margin: margin,
    numbering: none,
  )

  // Font settings
  set text(
    font: font,
    size: fontsize,
  )

  // Paragraph settings
  set par(justify: true)

  // Level 1 heading styling
  show heading.where(level: 1): it => block(
    stroke: (bottom: 1pt + brand-border),
    inset: (bottom: 0.3em),
    width: 100%,
    text(fill: brand-dark, weight: "bold", size: 1.1em, it.body),
  )

  // Level 2 heading styling
  show heading.where(level: 2): it => block(
    above: 1.2em,
    below: 0.6em,
    text(fill: brand-blue, weight: "bold", size: 1.1em, it.body)
  )

  // Level 3 heading styling
  show heading.where(level: 3): it => block(
    above: 0.6em,
    below: 0.8em,
    text(fill: brand-blue, weight: "semibold", size: 1.0em, it.body)
  )

  // Custom list marker styling
  set list(
    marker: (
      text(fill: brand-blue)[•],
      text(fill: brand-blue)[◦],
    ),
    spacing: 1.0em,
  )

  // Header & Abstract (Single column layout)
  if title != none {
    block(
      width: 100%,
      stroke: (bottom: 2pt + brand-border),
      inset: (bottom: 1.75em),
      below: 2.25em,
      [
        #text(
          fill: brand-dark,
          size: 2.75em,
          weight: "extrabold",
          tracking: -0.025em,
        )[#title]

        #if subtitle != none {
          v(-1.75em)
          text(
            fill: brand-blue,
            size: 1.35em,
            weight: "medium",
          )[#subtitle]
        }

        #if personal-info != none {
          // v(0.15em)
          text(
            fill: brand-grey,
            size: 0.95em,
            weight: "regular",
          )[#personal-info]
        }

        #if abstract != none {
          v(1.00em)
          block(
            width: 100%,
            fill: brand-light-bg,
            stroke: (left: 4pt + brand-blue),
            radius: (right: 8pt),
            inset: (x: 1.25em, y: 1.25em),
            text(
              fill: brand-grey,
              size: 1.05em,
              style: "italic",
            )[
              #set par(justify: true)
              #abstract
            ]
          )
        }
      ]
    )
  }

  // Main body content (formatted into columns if specified)
  if cols > 1 {
    columns(cols, gutter: 2em)[#doc]
  } else {
    doc
  }
}

// ---------------------------------------------------------------------------
// PANDOC TEMPLATE BINDING & GENERATION
//
// Binds Pandoc variables passed from Quarto's YAML header into the custom
// `conf` template function.
// ---------------------------------------------------------------------------

#show: doc => conf(
  title: [$title$],
  $if(subtitle)$
  subtitle: [$subtitle$],
  $endif$
  $if(personal-info)$
  personal-info: [$personal-info$],
  $endif$
  $if(abstract)$
  abstract: [$abstract$],
  $endif$
  $if(mainfont)$
  font: ("$mainfont$",),
  $else$
  font: ("Segoe UI",),
  $endif$
  $if(font-size)$
  fontsize: $font-size$,
  $else$
  fontsize: 10pt,
  $endif$
  $if(papersize)$
  paper: "$papersize$",
  $else$
  paper: "a4",
  $endif$
  $if(margin)$
  margin: ($for(margin/pairs)$$margin.key$: $margin.value$,$endfor$),
  $else$
  margin: (x: 1.0cm, y: 1.0cm),
  $endif$
  $if(page-numbering)$
  pagenumbering: "$page-numbering$",
  $else$
  pagenumbering: none,
  $endif$
  $if(columns)$
  cols: $columns$,
  $else$
  cols: 2,
  $endif$
  doc,
)

$body$

// ---------------------------------------------------------------------------
// EOF
// ---------------------------------------------------------------------------