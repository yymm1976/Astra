// Contour Shaders by Eleeter

#ifndef CONTOUR_OUTLINE_GLSL
#define CONTOUR_OUTLINE_GLSL

#define OUTLINE_NEAR_DIST 5.0 // [1.0 2.0 3.0 5.0 10.0 20.0]
#define OUTLINE_NEAR_PX 4.0 // [1.0 2.0 3.0 4.0 5.0 6.0 8.0 10.0]
#define OUTLINE_DARKNESS 0.30 // [0.0 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.0]
#define OUTLINE_MAX_RADIUS 6

#define OUTLINE_RAINBOW 0 // [0 1]
#define OUTLINE_RAINBOW_CYCLE 1 // [0 1]
#define OUTLINE_RAINBOW_HUE 0.00 // [0.00 0.05 0.10 0.17 0.25 0.33 0.42 0.50 0.58 0.67 0.75 0.83 0.92]
#define OUTLINE_RAINBOW_SPEED 1.00 // [0.25 0.50 0.75 1.00 1.50 2.00 3.00 4.00 5.00]

#define OUTLINE_REF_FOCAL 1.4281


vec3 HsvToRgb(float h, float s, float v)
{
    vec3 c = clamp(abs(fract(h + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), c, s);
}

float LinearDepth(float d)
{
    return (2.0 * near * far) / (far + near - (2.0 * d - 1.0) * (far - near));
}

float Mask(ivec2 c, bool hand) 
{
    vec2 m = texelFetch(colortex9, clamp(c, ivec2(0), ivec2(viewWidth, viewHeight) - 1), 0).rg;
    return hand ? m.g : m.r;
}

bool IsVaild(ivec2 q, bool hand, float src, float depthTol)
{
    if (Mask(q, hand) <= 0.01) 
    {
        return false;
    }
    
    if (hand) 
    {
        return true;
    }
    
    ivec2 hibye = ivec2(viewWidth, viewHeight) - 1;
    
    float nl = LinearDepth(texelFetch(depthtex0, clamp(q, ivec2(0), hibye), 0).r);
    return abs(nl - src) <= depthTol;
}

bool IsSolidSource(ivec2 c, bool hand, float src, float depthTol)
{
    bool r = IsVaild(c + ivec2( 1, 0), hand, src, depthTol);
    bool l = IsVaild(c + ivec2(-1, 0), hand, src, depthTol);
    bool u = IsVaild(c + ivec2( 0, 1), hand, src, depthTol);
    bool d = IsVaild(c + ivec2( 0,-1), hand, src, depthTol);
    if (!((r || l) && (u || d)))
    {
        return false;
    }

    return (r && u && IsVaild(c + ivec2( 1, 1), hand, src, depthTol))
        || (l && u && IsVaild(c + ivec2(-1, 1), hand, src, depthTol))
        || (r && d && IsVaild(c + ivec2( 1,-1), hand, src, depthTol))
        || (l && d && IsVaild(c + ivec2(-1,-1), hand, src, depthTol));
}

void DrawOutline(inout vec4 sceneColor) 
{
    vec2 centerMasks = texelFetch(colortex9, texelCoord, 0).rg;
    float entityMask = centerMasks.r;
    float handMask = centerMasks.g;
    float currentDepth = texelFetch(depthtex0, texelCoord, 0).r;

    float currentLinearDepth = LinearDepth(currentDepth);

    float perspectiveBias = 0.05 * abs(gbufferProjection[3][2])
                            / (currentLinearDepth * currentLinearDepth);

    float perspectiveSep = 0.4 * (OUTLINE_REF_FOCAL / gbufferProjection[1][1]);

    vec3 weightedColor = vec3(0.0);
    float totalWeight = 0.0;

    for (int y = -OUTLINE_MAX_RADIUS; y <= OUTLINE_MAX_RADIUS; y++)
    {
        for (int x = -OUTLINE_MAX_RADIUS; x <= OUTLINE_MAX_RADIUS; x++)
        {
            float distSq = float(x * x + y * y);
            if (distSq > float(OUTLINE_MAX_RADIUS * OUTLINE_MAX_RADIUS))
            {
                continue;
            }


            ivec2 sampleCoord  = texelCoord + ivec2(x, y);
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, ivec2(viewWidth, viewHeight))))
            {
                continue;
            }

            vec2 masks = texelFetch(colortex9, sampleCoord, 0).rg;
            float neighborMask = max(masks.r, masks.g);
            if (neighborMask < 0.01)
            {
                continue;
            }

            float neighborDepth = texelFetch(depthtex0, sampleCoord, 0).r;

            bool isValidEdge = false;
            if (masks.g > 0.01 && handMask < 0.5)
            {
                isValidEdge = true;
            } else if (entityMask < 0.5 && handMask < 0.5)
            {
                isValidEdge = (currentDepth >= neighborDepth - perspectiveBias);
            } else
            {
                float neighborLinearDepth = LinearDepth(neighborDepth);
                isValidEdge = (neighborLinearDepth < currentLinearDepth - perspectiveSep);
            }

            if (!isValidEdge)
            {
                continue;
            }

            float linearDist = LinearDepth(neighborDepth);
            float dynRadius = clamp(OUTLINE_NEAR_PX * (OUTLINE_NEAR_DIST / linearDist) * (gbufferProjection[1][1] / OUTLINE_REF_FOCAL), 1.0, float(OUTLINE_MAX_RADIUS)
            );

            if (distSq > dynRadius * dynRadius)
            {
                continue;
            }

            if (dynRadius > 1.001 && !IsSolidSource(sampleCoord, masks.g > 0.01, linearDist, 0.5 * perspectiveSep))
            {
                continue;
            }

            float sigma2 = dynRadius * dynRadius * 0.25;
            float gaussWeight = exp(-distSq / sigma2) * neighborMask;

            weightedColor += gaussWeight * texelFetch(colortex0, sampleCoord, 0).rgb;
            totalWeight += gaussWeight;
        }
    }

    if (totalWeight > 0.001)
    {
        vec3 outlineColor = weightedColor / totalWeight;

        #if OUTLINE_RAINBOW == 1
            #if OUTLINE_RAINBOW_CYCLE == 1
                float hue = fract(frameTimeCounter * OUTLINE_RAINBOW_SPEED * 0.1);
            #else
                float hue = OUTLINE_RAINBOW_HUE;
            #endif
            sceneColor.rgb = HsvToRgb(hue, 1.0, 1.0);
        #else
            sceneColor.rgb = outlineColor * OUTLINE_DARKNESS;
        #endif
        sceneColor.a = 1.0;
    }
}

#endif
