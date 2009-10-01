function string.unescape(url)
  url = string.gsub(url, "+", " ")
  url = string.gsub(url, "%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)  
  
  return url
end

function string.escape(s)
  s = string.gsub(s, "([&=+%c])", function (c)
    return string.format("%%%02X", string.byte(c))
  end)
  s = string.gsub(s, " ", "+")
  
  return s
end

function string.decodeEntities(s)
  local entities = {
    amp = "&",
    lt = "<",
    gt = ">",
    quot = "\"",
    apos = "'", 
    nbsp = " ",
    iexcl = "¡",
    cent = "¢",
    pound = "£",
    curren = "¤",
    yen = "¥",
    brvbar = "¦",
    sect = "§",
    uml = "¨",
    copy = "©",
    ordf = "ª",
    laquo = "«",
--    not = "¬",
    shy = "­",
    reg = "®",
    macr = "¯",
    deg = "°",
    plusmn = "±",
    sup2 = "²",
    sup3 = "³",
    acute = "´",
    micro = "µ",
    para = "¶",
    middot = "·",
    cedil = "¸",
    sup1 = "¹",
    ordm = "º",
    raquo = "»",
    frac14 = "¼",
    frac12 = "½",
    frac34 = "¾",
    iquest = "¿",
    times = "×",
    divide = "÷",   
  }
    
  return string.gsub(s, "&(%w+);", entities)
end

function string.caseInsensitive(s)
  s = string.gsub(s, "%a", function (c)
    return string.format("[%s%s]", string.lower(c), string.upper(c))
  end)
  return s
end
