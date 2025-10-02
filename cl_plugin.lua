ix.polydraw = ix.polydraw or {}

local DEGREES_TO_RADIANS = math.pi / 180
local TESSELLATION_STEPS = 16
local CORNER_SEGMENTS = 6

local function transformPoint(p, m)
    return {
        x = m[1] * p.x + m[3] * p.y + m[5],
        y = m[2] * p.x + m[4] * p.y + m[6]
    }
end

local function multiplyMatrices(m1, m2)
    return {
        m1[1] * m2[1] + m1[3] * m2[2],
        m1[2] * m2[1] + m1[4] * m2[2],
        m1[1] * m2[3] + m1[3] * m2[4],
        m1[2] * m2[3] + m1[4] * m2[4],
        m1[1] * m2[5] + m1[3] * m2[6] + m1[5],
        m1[2] * m2[5] + m1[4] * m2[6] + m1[6]
    }
end

local function parseTransform(str)
    if not str then return {1, 0, 0, 1, 0, 0} end
    
    local matrix = {1, 0, 0, 1, 0, 0}
    for type, args in str:gmatch("([%w_]+)%s*%(([^)]*)%)") do
        local nums = {}
        for n in args:gmatch("[%d%.e%-]+") do 
            table.insert(nums, tonumber(n)) 
        end
        
        if type == "translate" then
            local tx, ty = nums[1] or 0, nums[2] or 0
            matrix = multiplyMatrices(matrix, {1, 0, 0, 1, tx, ty})
        elseif type == "scale" then
            local sx, sy = nums[1] or 1, nums[2] or nums[1] or 1
            matrix = multiplyMatrices(matrix, {sx, 0, 0, sy, 0, 0})
        elseif type == "rotate" then
            local angle, cx, cy = (nums[1] or 0) * DEGREES_TO_RADIANS, nums[2] or 0, nums[3] or 0
            local cosA, sinA = math.cos(angle), math.sin(angle)
            local t1 = {1, 0, 0, 1, cx, cy}
            local r = {cosA, sinA, -sinA, cosA, 0, 0}
            local t2 = {1, 0, 0, 1, -cx, -cy}
            matrix = multiplyMatrices(matrix, multiplyMatrices(t1, multiplyMatrices(r, t2)))
        end
    end
    return matrix
end

local function getColorFromAttrs(attrs, type, overrideColor)
    if overrideColor then return overrideColor end
    if not attrs[type] or attrs[type] == "none" then return nil end

    local colorStr = attrs[type]
    local opacityStr = attrs[type .. "-opacity"]
    local r, g, b = 255, 255, 255
    
    if colorStr:sub(1, 1) == "#" then
        local hex = colorStr:sub(2)
        if #hex == 3 then
            hex = hex:gsub("(.)", "%1%1")
        end
        r = tonumber(hex:sub(1, 2), 16) or 255
        g = tonumber(hex:sub(3, 4), 16) or 255
        b = tonumber(hex:sub(5, 6), 16) or 255
    end
    
    local a = 255
    if opacityStr then
        a = math.Clamp((tonumber(opacityStr) or 1) * 255, 0, 255)
    end
    
    return Color(r, g, b, a)
end

local function parsePoints(str)
    local points = {}
    if not str then return points end
    
    for x, y in str:gmatch("([%d%.e%-]+)[%s,]*([%d%.e%-]+)") do
        table.insert(points, { x = tonumber(x), y = tonumber(y) })
    end
    return points
end

local function getPointOnQuadraticBezier(p0, p1, p2, t)
    local mt = 1 - t
    return {
        x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
        y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
    }
end

local function getPointOnCubicBezier(p0, p1, p2, p3, t)
    local mt = 1 - t
    return {
        x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x,
        y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y
    }
end

local function drawNode(node, parentMatrix, overrideColor)
    local localMatrix = parseTransform(node.attrs.transform)
    local matrix = multiplyMatrices(parentMatrix, localMatrix)

    local fill = getColorFromAttrs(node.attrs, "fill", overrideColor)
    local stroke = getColorFromAttrs(node.attrs, "stroke", overrideColor)
    local strokeWidth = tonumber(node.attrs["stroke-width"]) or 1

    local points = {}

    if node.type == "rect" then
        local x = tonumber(node.attrs.x) or 0
        local y = tonumber(node.attrs.y) or 0
        local w = tonumber(node.attrs.width) or 0
        local h = tonumber(node.attrs.height) or 0
        local rx = tonumber(node.attrs.rx) or 0
        local ry = tonumber(node.attrs.ry) or rx or 0

        rx = math.min(rx, w / 2)
        ry = math.min(ry, h / 2)

        if rx == 0 and ry == 0 then
            points = {
                {x = x, y = y},
                {x = x + w, y = y},
                {x = x + w, y = y + h},
                {x = x, y = y + h}
            }
        else
            for i = 0, CORNER_SEGMENTS do
                local angle = (i / CORNER_SEGMENTS) * math.pi / 2 - math.pi / 2
                table.insert(points, {x = x + w - rx + math.cos(angle) * rx, y = y + ry + math.sin(angle) * ry})
            end
            
            for i = 0, CORNER_SEGMENTS do
                local angle = (i / CORNER_SEGMENTS) * math.pi / 2
                table.insert(points, {x = x + w - rx + math.cos(angle) * rx, y = y + h - ry + math.sin(angle) * ry})
            end
            
            for i = 0, CORNER_SEGMENTS do
                local angle = (i / CORNER_SEGMENTS) * math.pi / 2 + math.pi / 2
                table.insert(points, {x = x + rx + math.cos(angle) * rx, y = y + h - ry + math.sin(angle) * ry})
            end
            
            for i = 0, CORNER_SEGMENTS do
                local angle = (i / CORNER_SEGMENTS) * math.pi / 2 + math.pi
                table.insert(points, {x = x + rx + math.cos(angle) * rx, y = y + ry + math.sin(angle) * ry})
            end
        end

    elseif node.type == "circle" or node.type == "ellipse" then
        local cx = tonumber(node.attrs.cx) or 0
        local cy = tonumber(node.attrs.cy) or 0
        local rx = tonumber(node.attrs.rx or node.attrs.r) or 0
        local ry = tonumber(node.attrs.ry or node.attrs.r) or 0

        for i = 0, TESSELLATION_STEPS * 2 do
            local angle = (i / (TESSELLATION_STEPS * 2)) * math.pi * 2
            table.insert(points, {x = cx + math.cos(angle) * rx, y = cy + math.sin(angle) * ry})
        end

    elseif node.type == "line" then
        local x1 = tonumber(node.attrs.x1) or 0
        local y1 = tonumber(node.attrs.y1) or 0
        local x2 = tonumber(node.attrs.x2) or 0
        local y2 = tonumber(node.attrs.y2) or 0
        
        points = {
            {x = x1, y = y1},
            {x = x2, y = y2}
        }

    elseif node.type == "polygon" or node.type == "polyline" then
        points = parsePoints(node.attrs.points)

    elseif node.type == "path" then
        local d = node.attrs.d or ""
        local current = {x = 0, y = 0}
        local start = {x = 0, y = 0}
        local pathPoints = {}
        local subPath = {}

        for cmd, args in d:gmatch("([MLHVCSQTAZ])([^MLHVCSQTAZ]*)") do
            local params = {}
            for num in args:gmatch("[%d%.e%-]+") do
                table.insert(params, tonumber(num))
            end

            if cmd == "M" then

                if #subPath > 0 then
                    table.insert(pathPoints, subPath)
                    subPath = {}
                end
                for i = 1, #params, 2 do
                    current = {x = params[i], y = params[i+1]}
                    if i == 1 then start = {x = current.x, y = current.y} end
                    table.insert(subPath, {x = current.x, y = current.y})
                end
            elseif cmd == "L" then

                for i = 1, #params, 2 do
                    current = {x = params[i], y = params[i+1]}
                    table.insert(subPath, {x = current.x, y = current.y})
                end
            elseif cmd == "H" then

                for i = 1, #params do
                    current = {x = params[i], y = current.y}
                    table.insert(subPath, {x = current.x, y = current.y})
                end
            elseif cmd == "V" then

                for i = 1, #params do
                    current = {x = current.x, y = params[i]}
                    table.insert(subPath, {x = current.x, y = current.y})
                end
            elseif cmd == "Z" then

                if #subPath > 0 then
                    table.insert(subPath, {x = start.x, y = start.y})
                    current = {x = start.x, y = start.y}
                end
            end
        end

        if #subPath > 0 then
            table.insert(pathPoints, subPath)
        end
        
        points = pathPoints
    end

    if node.type == "path" then
        for _, subPath in ipairs(points) do
            local transformedPoints = {}
            for _, point in ipairs(subPath) do
                table.insert(transformedPoints, transformPoint(point, matrix))
            end
            
            if fill and #transformedPoints >= 3 then
                surface.SetDrawColor(fill)
                surface.DrawPoly(transformedPoints)
            end
            
            if stroke and strokeWidth > 0 and #transformedPoints >= 2 then
                surface.SetDrawColor(stroke)
                for i = 1, #transformedPoints - 1 do
                    surface.DrawLine(
                        transformedPoints[i].x, transformedPoints[i].y,
                        transformedPoints[i+1].x, transformedPoints[i+1].y
                    )
                end
            end
        end
    else
        local transformedPoints = {}
        for _, point in ipairs(points) do
            table.insert(transformedPoints, transformPoint(point, matrix))
        end

        if fill and #transformedPoints >= 3 then
            surface.SetDrawColor(fill)
            surface.DrawPoly(transformedPoints)
        end

        if stroke and strokeWidth > 0 then
            surface.SetDrawColor(stroke)
            if #transformedPoints >= 2 then
                for i = 1, #transformedPoints - 1 do
                    surface.DrawLine(
                        transformedPoints[i].x, transformedPoints[i].y,
                        transformedPoints[i+1].x, transformedPoints[i+1].y
                    )
                end
            end

            if node.type == "polygon" and #transformedPoints >= 3 then
                surface.DrawLine(
                    transformedPoints[#transformedPoints].x, transformedPoints[#transformedPoints].y,
                    transformedPoints[1].x, transformedPoints[1].y
                )
            end
        end
    end

    if node.children then
        for _, child in ipairs(node.children) do
            drawNode(child, matrix, overrideColor)
        end
    end
end

function ix.polydraw.parseSVG(svgString)
    local tree = { type = "svg", attrs = {}, children = {} }
    local stack = { tree }

    local function parseAttrs(str)
        local attrs = {}
        for key, value in str:gmatch("([%w%-:]+)%s*=%s*\"(.-)\"") do
            attrs[key] = value
        end
        return attrs
    end

    for tag, attrs, selfClose in svgString:gmatch("<(%/?[%w:]+)(.-)(/?)>") do
        local isClosing = tag:sub(1, 1) == "/"
        local tagName = isClosing and tag:sub(2) or tag

        if not isClosing then
            local node = { type = tagName, attrs = parseAttrs(attrs), children = {} }
            table.insert(stack[#stack].children, node)
            
            if selfClose ~= "/" and tagName ~= "path" and tagName ~= "rect" and tagName ~= "circle" and tagName ~= "ellipse" and tagName ~= "line" and tagName ~= "polygon" and tagName ~= "polyline" then
                table.insert(stack, node)
            end
        else
            if #stack > 1 then
                table.remove(stack)
            end
        end
    end

    return tree
end

function ix.polydraw.paint(tree, x, y, w, h, overrideColor)
    local sceneWidth, sceneHeight
    
    if tree.attrs.viewBox then
        local _, _, vbW, vbH = tree.attrs.viewBox:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
        sceneWidth, sceneHeight = tonumber(vbW), tonumber(vbH)
    else
        sceneWidth, sceneHeight = tonumber(tree.attrs.width), tonumber(tree.attrs.height)
    end
    
    sceneWidth = sceneWidth or w
    sceneHeight = sceneHeight or h
    
    if sceneWidth == 0 or sceneHeight == 0 then return end
    
    local scaleX, scaleY = w / sceneWidth, h / sceneHeight
    local initialMatrix = {scaleX, 0, 0, scaleY, x, y}
    
    if tree.children then
        for _, child in ipairs(tree.children) do
            drawNode(child, initialMatrix, overrideColor)
        end
    end
end