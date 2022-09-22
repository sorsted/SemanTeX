-- aliases for protected environments
local assert, io_open
    = assert, io.open

-- load the ltn12 module
local ltn12 = require("ltn12")

-- No more global accesses after this point
if _VERSION == "Lua 5.2" then _ENV = nil end

-- copy a file
copy_file = function(path_src, path_dst)
  ltn12.pump.all(
      ltn12.source.file(assert(io_open(path_src, "rb"))),
      ltn12.sink.file(assert(io_open(path_dst, "wb")))
    )
end

openFile = function(file)
 f = io.open(file, "r")
 filecontent = f:read("*all")
 local beginDocPosition = filecontent:find('\\begin{document}')
 if not beginDocPosition then
	tex.sprint( [[\begingroup\ExplSyntaxOn
		\msg_fatal:nnn { stripsemantex } { begin_document_not_found } { ]] .. file .. [[ }
		\endgroup]] )
	return
 end
 precontent = filecontent:sub(1,beginDocPosition-1)
 content = filecontent:sub(beginDocPosition,-1)
 f:close()
end

closeFile = function(file)
 f = io.open(file, "w")
 f:write(precontent .. content)
 f:close()
end

removeStricttexFormatting = function(str)
	-- We do this in case the package "stricttex" was used
	str = str:gsub('numberZERO','0')
	str = str:gsub('numberONE','1')
	str = str:gsub('numberTWO','2')
	str = str:gsub('numberTHREE','3')
	str = str:gsub('numberFOUR','4')
	str = str:gsub('numberFIVE','5')
	str = str:gsub('numberSIX','6')
	str = str:gsub('numberSEVEN','7')
	str = str:gsub('numberEIGHT','8')
	str = str:gsub('numberNINE','9')
	str = str:gsub('symbolPRIME','\'')
	return str
end

addIDsToRegisters = function(str)
	str = removeStricttexFormatting(str)
	content = content:gsub('\\' .. str .. '([^%a])' ,'\\SemantexID{}\\' .. str .. '%1')
	-- '%f[^%a]' does not work here, as it will not react if the last character of str is a number,
	-- which stricttex allows.
	-- Because of this choice, there will be an issue if you use stricttex and let
	-- \<command> by a SemanTeX command and \<command>' be a non-SemanTeX command.
	-- So simply *don't do that*.
end

removeSuperfluousIDs = function()
	local p = content:find('([^\\]%%[^\n]-)\\SemantexID{}([^\n]-\n)')
	while p do
		content = content:gsub('([^\\]%%[^\n]-)\\SemantexID{}([^\n]-\n)','%1%2')
		p = content:find('([^\\]%%[^\n]-)\\SemantexID{}([^\n]-\n)')
	end
	content = content:gsub('parent(%s*)=(%s*)\\SemantexID{}','parent%1=%2')
	content = content:gsub('class(%s*)=(%s*)\\SemantexID{}','class%1=%2')
	content = content:gsub('clone(%s*)=(%s*)\\SemantexID{}','clone%1=%2')
	content = content:gsub('copy(%s*)=(%s*)\\SemantexID{}','copy%1=%2')
	content = content:gsub('\\New(%w+)Class(%s*{?)\\SemantexID{}','\\New%1Class%2')
	content = content:gsub('\\NewObject(%s*{?%s*)\\SemantexID{}(\\%w+%s*}?%s*{?%s*)\\SemantexID{}', '\\NewObject%1%2')
	content = content:gsub('\\SetupClass(%s*{?%s*)\\SemantexID{}', '\\SetupClass%1')
	content = content:gsub('\\SetupObject(%s*{?%s*)\\SemantexID{}', '\\SetupObject%1')
end

addNumbersToIDs = function()
	local n = 0
	local p,q = string.find(content,'\\SemantexID{}')
	while q do
		n = n + 1
		content = content:sub(1,q-1) .. n .. content:sub(q,-1)
		p, q = string.find(content,'\\SemantexID{}')	
	end
end

semantexIDluacommand = function(id, source, output)
	local p, q = string.find(content, '\\SemantexID{' .. id .. '}')
	
	while p do
		content = content:sub(1,p-1) .. content:sub(q+1,-1)
		
		source = source:gsub('%s+', '')
		
		-- We do this in case the package "stricttex" was used
		source = removeStricttexFormatting(source)
		
		-- This is because #1's in the code becomes ##1
		-- in the .semtex file.
		source = source:gsub('#(%d)', '%1')
		
		local length = source:len()
	
		local i = 1
		
		local s
		
		while i <= length do
			s = content:sub(p,p)
			if s == source:sub(i,i) then
				content = content:sub(1 , p-1) .. content:sub(p+1, -1)
				i = i + 1
			elseif s:match('%s') then
				content = content:sub(1, p-1) .. content:sub(p+1, -1)
			elseif s == '%' then
				content = content:sub(1 , p-1) .. content:sub(p,-1):gsub('%%.-\n','',1)
			elseif s == '{' then
				-- In this case, we remove the corresponding right brace,
				-- once we find it
				local netto = 1 -- The current brace group level
				local q = 0 -- The position we have moved forward so far
				while netto > 0 do
					q = q + 1
					local e = content:sub(p+q,p+q)
					if e == '}' then
						netto = netto - 1
					elseif e == '{' then
						netto = netto + 1
					elseif e == '\\' then
						q = q + 1
					elseif e == '%' then
						content = content:sub(1, p+q-1) .. content:sub(p+q,-1):gsub('%%.-\n','',1)
						q = q - 1
					end
				end
				content = content:sub(1,p-1) .. content:sub(p+1,p+q-1) .. content:sub(p+q+1,-1)
			elseif s == '<' and content:sub(p+1,p+2) == '[>' then
				content = content:sub(1,p-1) .. content:sub(p+3,-1)
				i = i + 1
			elseif s == '<' and content:sub(p+1,p+2) == ']>' then
				content = content:sub(1,p-1) .. content:sub(p+3,-1)
				i = i + 1
			elseif source:sub(i,i) == '{' then
				-- In this case, we remove the corresponding right brace,
				-- once we find it
				local netto = 1 -- The current brace group level
				local q = 0 -- The position we have moved forward so far
				while netto > 0 do
					q = q + 1
					local e = source:sub(i+q,i+q)
					if e == '}' then
						netto = netto - 1
					elseif e == '{' then
						netto = netto + 1
					elseif e == '\\' then
						q = q + 1
					-- there is no chance that the source contains an unescaped %, so we do not
					-- check for this
					end
				end
				source = source:sub(1,i-1) .. source:sub(i+1,i+q-1) .. source:sub(i+q+1,-1)
				length = source:len()
			else
				tex.sprint( [[\begingroup\ExplSyntaxOn
				\msg_fatal:nnnn { stripsemantex } { source_not_expected } { ]] .. source:sub(i,i) .. [[ } { ]] .. s  .. [[ }
				\endgroup]] )
				break
			end
		end
		
		
		output = output:gsub('%s*\\sp {', '^{')
		output = output:gsub('%s*\\sb {', '_{')
		output = output:gsub('\\mathopen \\big ', '\\bigl')
		output = output:gsub('\\mathclose \\big ', '\\bigr')
		output = output:gsub('\\mathopen \\Big ', '\\Bigl')
		output = output:gsub('\\mathclose \\Big ', '\\Bigr')
		output = output:gsub('\\mathopen \\bigg ', '\\biggl')
		output = output:gsub('\\mathclose \\bigg ', '\\biggr')
		output = output:gsub('\\mathopen \\Bigg ', '\\Biggl')
		output = output:gsub('\\mathclose \\Bigg ', '\\Biggr')
		output = output:gsub('\\mathopen %(', '(')
		output = output:gsub('\\mathclose %)', ')')
		output = output:gsub('\\mathopen %[', '[')
		output = output:gsub('\\mathclose %]', ']')
		output = output:gsub('\\mathopen \\{', '\\{')
		output = output:gsub('\\mathclose \\}', '\\}')
		output = output:gsub('\\mathopen \\lbrace', '\\lbrace')
		output = output:gsub('\\mathclose \\rbrace', '\\rbrace')
		output = output:gsub('\\mathopen \\lbrack', '\\lbrack')
		output = output:gsub('\\mathclose \\rbrack', '\\rbrack')
		output = output:gsub('\\mathopen \\langle', '\\langle')
		output = output:gsub('\\mathclose \\rangle', '\\rangle')
		output = output:gsub('\\mathopen \\lvert', '\\lvert')
		output = output:gsub('\\mathclose \\rvert', '\\rvert')
		output = output:gsub('\\mathopen \\vert', '\\lvert')
		output = output:gsub('\\mathclose \\vert', '\\rvert')
		output = output:gsub('\\mathopen \\lVert', '\\lVert')
		output = output:gsub('\\mathclose \\rVert', '\\rVert')
		output = output:gsub('\\mathopen \\Vert', '\\lVert')
		output = output:gsub('\\mathclose \\Vert', '\\rVert')
		output = output:gsub('%^{\\prime }', '\'')
		output = output:gsub('%^{\\prime \\prime }', '\'\'')
		output = output:gsub('%^{\\prime \\prime \\prime }', '\'\'\'')
		output = output:gsub('%^{\\prime \\prime \\prime \\prime }', '\'\'\'\'')
		output = output:gsub('%^{\\prime \\prime \\prime \\prime \\prime }', '\'\'\'\'\'')
		
		output = output:gsub('%s+%f[{}%[%]%(%)%$,]','')
		output = output:gsub('([}%]%)])%f[\\%w%+%-%(%[=]', '%1 ')
		output = output:gsub(',',', ')
		output = output:gsub('%s+$', '')
		
		
		-- We now check whether the string we add will follow right
		-- after a control sequence, causing it to be interpreted
		-- as part of that control sequence.
		-- Because we want to allow the user to use stricttex, we
		-- check for alphanumerical control sequences rather than
		-- just alphabetic ones. This could add spaces that
		-- the user might not have intended, but it's a minor issue.
		if output:sub(1,1):match('%w') and content:sub(1, p-1):match('\\%w+$') then
			content = content:sub(1,p-1) .. ' ' .. output .. content:sub(p,-1)
		else
			content = content:sub(1,p-1) .. output .. content:sub(p,-1)
		end
		p, q = string.find(content, '\\SemantexID{' .. id .. '}')
	end
end

stripRemainingSemantexIDs = function()
	content = content:gsub('\\SemantexID{%d+}', '')
end

removeParenthesisCommands = function()
	content = content:gsub('\\SemantexMathOpen \\bigg%s?', '\\biggl')
	content = content:gsub('\\SemantexMathClose \\bigg%s?', '\\biggr')
	content = content:gsub('\\SemantexMathOpen \\Bigg%s?', '\\Biggl')
	content = content:gsub('\\SemantexMathClose \\Bigg%s?', '\\Biggr')
	content = content:gsub('\\SemantexMathOpen \\big%s?', '\\bigl')
	content = content:gsub('\\SemantexMathClose \\big%s?', '\\bigr')
	content = content:gsub('\\SemantexMathOpen \\Big%s?', '\\Bigl')
	content = content:gsub('\\SemantexMathClose \\Big%s?', '\\Bigr')
	content = content:gsub('\\SemantexMathOpen{} %(', '(')
	content = content:gsub('%s*\\SemantexMathClose{}%)', ')')
	content = content:gsub('\\SemantexMathOpen{} %[', '[')
	content = content:gsub('%s*\\SemantexMathClose{}%]', ']')
	content = content:gsub('\\SemantexMathOpen{} \\{', '\\{')
	content = content:gsub('%s*\\SemantexMathClose{} \\}', '\\}')
	content = content:gsub('\\SemantexMathOpen{} \\lbrace', '\\lbrace')
	content = content:gsub('\\SemantexMathClose{} \\rbrace', '\\rbrace')
	content = content:gsub('\\SemantexMathOpen{} \\lbrack', '\\rbrack')
	content = content:gsub('\\SemantexMathClose{} \\rbrack', '\\rbrack')
	content = content:gsub('\\SemantexMathOpen{} \\langle', '\\langle')
	content = content:gsub('\\SemantexMathClose{} \\rangle', '\\rangle')
	content = content:gsub('\\SemantexMathOpen{} \\lvert', '\\lvert')
	content = content:gsub('\\SemantexMathClose{} \\rvert', '\\rvert')
	content = content:gsub('\\SemantexMathOpen{} \\vert', '\\lvert')
	content = content:gsub('\\SemantexMathClose{} \\vert', '\\rvert')
	content = content:gsub('\\SemantexMathOpen{} \\lVert', '\\lVert')
	content = content:gsub('\\SemantexMathClose{} \\rVert', '\\rVert')
	content = content:gsub('\\SemantexMathOpen{} \\Vert', '\\lVert')
	content = content:gsub('\\SemantexMathClose{} \\Vert', '\\rVert')
	content = content:gsub('\\SemantexMathOpen{} .%s?', '')
	content = content:gsub('\\SemantexMathClose{} .%s?', '')
	content = content:gsub('\\SemantexMathOpen{}', '\\mathopen ')
	content = content:gsub('\\SemantexMathClose{}', '\\mathclose ')
	content = content:gsub('\\SemantexMathOpenAuto%s?', '\\SemantexLeft')
	content = content:gsub('\\SemantexMathCloseAuto%s?', '\\SemantexRight')
	content = content:gsub('\\SemantexMathOpenNoPar%s?', '')
	content = content:gsub('\\SemantexMathCloseNoPar%s?', '')
	content = content:gsub('\\SemantexMathOpen%s?', '\\mathopen')
	content = content:gsub('\\SemantexMathClose%s?', '\\mathclose')
end

stripComments = function()
	content = content:gsub('\\%%', '\\StripSemantexEscapedPercent')
	content = content:gsub('(\\%w+)%%.-\n%s*', '%1 ')
	content = content:gsub('%%.-\n%s*', '')
	content = content:gsub('\\StripSemantexEscapedPercent', '\\%%')
end

addSemtexPackageToFile = function()
	content = [[% The following was added by "stripsemantex":

\usepackage{semtex,leftindex,graphicx}

\providecommand\SemantexLeft{%
	\mathopen{}\mathclose\bgroup\left
}

\providecommand\SemantexRight{%
	\aftergroup\egroup\right
}

\makeatletter
\DeclareRobustCommand\SemantexBullet{%
  \mathord{\mathpalette\SemantexBullet@{0.5}}%
}
\newcommand\SemantexBullet@[2]{%
  \vcenter{\hbox{\scalebox{#2}{$\m@th#1\bullet$}}}%
}
\DeclareRobustCommand\SemantexDoubleBullet{\SemantexBullet \SemantexBullet}
\makeatother

]] .. content
end