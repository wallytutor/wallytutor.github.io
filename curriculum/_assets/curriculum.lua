function Div(el)
  if FORMAT == 'typst' then
    if el.classes:includes('education-entry') then
      local content = pandoc.List({ pandoc.RawBlock('typst', '#education-entry[') })
      content:extend(el.content)
      content:insert(pandoc.RawBlock('typst', ']'))
      return content
    elseif el.classes:includes('experience-entry') then
      local content = pandoc.List({ pandoc.RawBlock('typst', '#experience-entry[') })
      content:extend(el.content)
      content:insert(pandoc.RawBlock('typst', ']'))
      return content
    elseif el.classes:includes('inline-dl') then
      local content = pandoc.List({ pandoc.RawBlock('typst', '#inline-dl[') })
      content:extend(el.content)
      content:insert(pandoc.RawBlock('typst', ']'))
      return content
    end
  end
end
