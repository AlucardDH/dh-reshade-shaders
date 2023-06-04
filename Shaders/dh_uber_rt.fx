////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://github.com/AlucardDH/dh-reshade-shaders
//
////////////////////////////////////////////////////////////////////////////////////////////////
#include "Reshade.fxh"

// VISIBLE PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////

// Define the working resolution of the intermediate steps of the shader
// Default is 0.5. 1.0 for full-res, 0.5 for quarter-res
// It can go lower for a performance boost like 0.25 but the image will be more blurry and noisy
// It can go higher (lile 2.0) if you have GPU to spare
#ifndef DH_RENDER_SCALE
 #define DH_RENDER_SCALE 0.5
#endif

#define GI_PROBE 0

// HIDDEN PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////
// Should not be modified but can help if you really want to squeeze some FPS at the cost of lower fidelity

// Define the maximum distance a ray can travel
// Default is 1.0 : the full screen/depth, less (0.5) can be enough depending on the game
#define OPTIMIZATION_RT_MAX_DISTANCE 1.0

#define OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO 3

// Define is the roughness is actived
// Default is 1 (activated), can be deactivated
#define ROUGHNESS 1

// Define is a light smoothing filter on Normal
// Default is 1 (activated)
#define NORMAL_FILTER 1

#define TEX_NOISE (__RENDERER__==0x9000)
#define OPTIMIZATION_ONE_LOOP_RT (__RENDERER__==0x9000)

// CONSTANTS /////////////////////////////////////////////////////////////////
// Don't touch this

#define DEBUG_OFF 0
#define DEBUG_GI 1
#define DEBUG_AO 2
#define DEBUG_SSR 3
#define DEBUG_ROUGHNESS 4
#define DEBUG_DEPTH 5
#define DEBUG_NORMAL 6
#define DEBUG_SKY 7
#define DEBUG_MOTION 8

#define RT_HIT 1.0
#define RT_HIT_SKY -0.5
#define RT_MISSED -1.0
#define RT_MISSED_FAST -2.0

#define PI 3.14159265359
#define SQRT2 1.41421356237

// Can be used to fix wrong screen resolution
#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT

#define RENDER_WIDTH INPUT_WIDTH*DH_RENDER_SCALE
#define RENDER_HEIGHT INPUT_HEIGHT*DH_RENDER_SCALE

#define RENDER_SIZE int2(RENDER_WIDTH,RENDER_HEIGHT)

#define BUFFER_SIZE int2(INPUT_WIDTH,INPUT_HEIGHT)
#define BUFFER_SIZE3 int3(INPUT_WIDTH,INPUT_HEIGHT,INPUT_WIDTH*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier/1024)


// MACROS /////////////////////////////////////////////////////////////////
// Don't touch this
#define getNormal(c) (tex2Dlod(normalSampler,float4(c.xy,0,0)).xyz-0.5)*2
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4(c,0,0))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4(c.xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4(c.xy,0,0))
#define maxOf3(a) max(max(a.x,a.y),a.z)
#define minOf3(a) min(min(a.x,a.y),a.z)
#define getBrightness(color) maxOf3(color)
#define getPureness(color) (maxOf3(color)-minOf3(color))
//////////////////////////////////////////////////////////////////////////////

texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler sTexMotionVectorsSampler { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

namespace DH_UBER_RT {

// Textures

    // Common textures

#if TEX_NOISE
    texture blueNoiseTex < source ="dh_rt_noise.png" ; > { Width = 512; Height = 512; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex;  AddressU = REPEAT;  AddressV = REPEAT;  AddressW = REPEAT;};
#endif

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
#if GI_PROBE
    texture giProbeTex { Width = RENDER_WIDTH/16; Height = RENDER_HEIGHT/16; Format = RGBA8; MipLevels = 6; };
    sampler giProbeSampler { Texture = giProbeTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
#endif

    texture giPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giPassSampler { Texture = giPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 9; };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 9.0f;};
    
    texture giAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler giAccuSampler { Texture = giAccuTex; };

    // SSR textures
#if ROUGHNESS
    texture roughnessTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler roughnessSampler { Texture = roughnessTex; };
#endif
    
    texture ssrPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler ssrPassSampler { Texture = ssrPassTex; MinLOD = 0.0f; MaxLOD = 5.0f; };

    texture ssrSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler ssrSmoothPassSampler { Texture = ssrSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f; };
    
    texture ssrAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler ssrAccuSampler { Texture = ssrAccuTex; };
    

// Internal Uniforms
    uniform int framecount < source = "framecount"; >;
    uniform int random < source = "random"; min = 0; max = 512; >;

// Parameters

/*
    uniform bool bTest = true;
    uniform float fTest <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.99;
    uniform float fTest2 <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.99;
    uniform int iTest <
        ui_type = "slider";
        ui_min = 1; ui_max = 64;
        ui_step = 1;
    > = 1;
    uniform bool bTest2 = true;
    uniform bool bTest3 = true;
*/

    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0GI\0AO\0SSR\0Roughness\0Depth\0Normal\0Sky\0Motion\0";
        ui_tooltip = "Debug the intermediate steps of the shader";
    > = 0;
    
// DEPTH

    uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Depth multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.1;
        ui_tooltip = "Multiply the depth returned by the game\n"
                    "Can help to make mutitple shaders work together";
    > = 1.0;

    uniform float fSkyDepth <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Sky Depth";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define where the sky starts to prevent if to be affected by the shader";
    > = 0.99;
    
    uniform float fWeaponDepth <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Weapon Depth ";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define where the first person weapon ends";
    > = 0.001;
    
// COMMMON RT
// MOTION
    uniform bool bRTHitFast <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Opti Fast hit";
        ui_tooltip = "";
    > = true;
    
    uniform int iRTCheckHitPrecision <
        ui_category = "Common RT";
        ui_type = "slider";
        ui_label = "RT Hit precision";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES\n";
    > = 12;
    
    uniform int iCheckerboardRT <
        ui_category = "Common RT";
        ui_type = "combo";
        ui_label = "Checkerboard ray tracing";
        ui_items = "Disabled\0Half per frame\0Quarter per frame\0";
        ui_tooltip = "One ray per pixel, 1 ray per 2-pixels or 1 ray per 4-pixels\n"
                    "Lower=less ghosting, less performance\n"
                    "Higher=more ghosting, less noise, better performance\n"
                    "POSITIVE INPACT ON PERFORMANCES";
    > = 0;

    uniform int iFrameAccu <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 8;
    
    uniform float fRayStepPrecision <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Step Precision";
        ui_min = 100.0; ui_max = 2000;
        ui_step = 0.1;
        ui_tooltip = "Define the length of the steps during ray tracing.\n"
                    "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES\n"
                    "DEPENDING ON 'Step multiply'";
    > = 1000;

#if !OPTIMIZATION_ONE_LOOP_RT
    uniform int iRTMaxRays <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Max rays per pixel";
        ui_min = 1; ui_max = 4;
        ui_step = 1;
        ui_tooltip = "Maximum number of rays from 1 pixel if the first miss\n"
                    "Lower=Darker image, better performance\n"
                    "Higher=Less noise, brighter image\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 3;
    
    uniform float fRTMinRayBrightness <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Min ray brightness";
        ui_min = 0.01; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define the minimum brightness of a ray to not retry.\n"
                    "Lower=Darker image, better performance\n"
                    "Higher=Less noise, brighter image\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 0.2;
#endif
    
// GI

    uniform float fGIDistancePower <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Distance power";
        ui_min = 0; ui_max = 4.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the light intensity decrease";
    > = 2.0;
    
    uniform float fSkyColor <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Sky color";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the sky can brighten the scene";
    > = 0.2;
    
    uniform float fGIDarkAmplify <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Dark color compensation";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Brighten dark colors, useful in dark corners";
    > = 0.0;
    
    uniform float fGIBounce <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Bounce intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define if GI bounces in following frames";
    > = 0.5;

// AO
    
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
        ui_tooltip = "Define the intensity of AO";
    > = 1.5;
    
    uniform int iAODistance <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Distance";
        ui_min = 0; ui_max = BUFFER_WIDTH;
        ui_step = 1;
    > = BUFFER_WIDTH;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Pow";
        ui_min = 0.001; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 0.5;
    
    uniform float fAOLightProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Light protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of bright areas to avoid washed out highlights";
    > = 0.1;
    
    uniform float fAODarkProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Dark protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of dark areas to avoid totally black and unplayable parts";
    > = 0.1;
    


    // SSR
    uniform bool bSSR <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Enable SSR";
        ui_tooltip = "Toggle SSR";
    > = true;
    
#if ROUGHNESS
    uniform bool bRoughness <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness";
        ui_tooltip = "Tries to generate a roughness map of the image to have different type of reflections for SSR"
                    "/!\\ HAS A VAIRABLE INPACT ON PERFORMANCES";
    > = true;

    uniform int iRoughnessRadius <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness Radius";
        ui_min = 1; ui_max = 4;
        ui_step = 2;
        ui_tooltip = "Define the max distance of roughness computation.\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    uniform float fRoughnessIntensity <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness Intensity";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define the way reflections are blurred by rough surfaces";
    > = 0.25;
#endif

    // Denoising
    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Radius";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Define the max distance of smoothing.\n"
                    "Higher:less noise, less performances\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 2;
    
    uniform int iSmoothStep <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Step";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Compromise smoothing by skipping pixels in the smoothing and using lower quality LOD.\n"
                    "Higher:less noise, can smooth surfaces that should not be mixed\n"
                    "This has no impact on performances :)";
    > = 3;
    
    uniform int iSmoothSSRRadius <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "SSRRadius";
        ui_min = 0; ui_max = 4;
        ui_step = 1;
        ui_tooltip = "Define the max distance of smoothing.\n"
                    "Higher:less noise, less performances\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    
    uniform int iSmoothSSRStep <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "SSR Step";
        ui_min = 0; ui_max = 8;
        ui_step = 0;
        ui_tooltip = "Same as 'Step' but for SSR\n"
                    "Higher:less noise, can smooth surfaces that should not be mixed\n"
                    "This has no impact on performances :)";
    > = 0;
    
    uniform float fSmoothDistPow <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Distance Weight";
        ui_min = 0.001; ui_max = 8.00;
        ui_step = 0.001;
        ui_tooltip = "During denoising, give more importance to close of far pixels";
    > = 3.0;

    uniform float fNormalWeight <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Normal weight";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "During denoising, give more importance to pixels in the same orientation\n"
                    "Higher will make GI less blurry\n"
                    "Lower will make curved geometry smoother";
    > = 0.50;
    
    // Merging
        
    uniform float fDistanceFading <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Distance fading";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Distance from where the effect is less applied.";
    > = 0.9;
    
    uniform float fBaseColor <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Base color brightness";
        ui_min = 0.0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Simple multiplier for the base image.";
    > = 0.85;
        
    uniform float fGILightMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Light";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much bright areas are affected by GI.";
    > = 0.15;
    uniform float fGIDarkMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Dark";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much dark areas are affected by GI.";
    > = 0.75;
    
    uniform float fGIFinalMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Final merging";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the whole image is affected by GI.";
    > = 1.0;
    
    uniform bool bGIHDR <
        ui_category = "Merging";
        ui_label = "GI Dynamic darks";
        ui_tooltip = "Enable to adapt GI in the dark relative to screen average brigthness.";
    > = true;
    
    uniform float fMergingSSR <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "SSR";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define this intensity of the Screan Space Reflection.";
    > = 0.3;

#if ROUGHNESS
    uniform float fMergingRoughness <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "SSR Roughness";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define how much the roughness decrease reflection intensity";
    > = 0.5;
#endif

    uniform int iBlackLevel <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Black level ";
        ui_min = 0; ui_max = 255;
        ui_step = 0.001;
    > = 10;
    
    uniform int iWhiteLevel <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "White level";
        ui_min = 0; ui_max = 255;
        ui_step = 0.001;
    > = 245;

// FUCNTIONS

    float safePow(float value, float power) {
        return pow(abs(value),power);
    }

// Colors
    float3 RGBtoHSV(float3 c) {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
    }
    
    float3 HSVtoRGB(float3 c) {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

// Screen
    
    float2 RenderPixelSize() {
        return 1.0/float2(RENDER_WIDTH,RENDER_HEIGHT);
    }
    
    bool inScreen(float3 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0
            && coords.z>=0.0 && coords.z<=1.0;
    }
    
    float3 getWorldPosition(float2 coords,float depth) {
        float3 result = float3((coords-0.5)*depth,depth);
        result *= BUFFER_SIZE3;
        return result;
    }
    
    float3 getWorldPositionForNormal(float2 coords) {
        float depth = ReShade::GetLinearizedDepth(coords);
        float3 result = float3((coords-0.5)*depth,depth);
        if(depth<fWeaponDepth) {
            result.z /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
        }
        result *= BUFFER_SIZE3;
        return result;
    }

    float3 getScreenPosition(float3 wp) {
        float3 result = wp/BUFFER_SIZE3;
        result.xy /= result.z;
        return float3(result.xy+0.5,result.z);
    }

    float3 computeNormal(float2 coords,float3 offset) {
        float3 posCenter = getWorldPositionForNormal(coords);
        float3 posNorth  = getWorldPositionForNormal(coords - offset.zy);
        float3 posEast   = getWorldPositionForNormal(coords + offset.xz);
        return  normalize(cross(posCenter - posNorth, posCenter - posEast));
    }


#if ROUGHNESS
    float getRoughness(float2 coords) {
        return abs(getColorSampler(roughnessSampler,coords).r-0.5)*2;
    }
#endif


// Vector operations
    int getPixelIndex(float2 coords,int2 size) {
        int2 pxCoords = coords*size;
        pxCoords += random*int2(SQRT2,PI);
        pxCoords %= size;
        
        return pxCoords.x+pxCoords.y*size.x;
    }

#if !TEX_NOISE
    float randomValue(inout uint seed) {
        seed = seed * 747796405 + 2891336453;
        uint result = ((seed>>((seed>>28)+4))^seed)*277803737;
        result = (result>>22)^result;
        return result/4294967295.0;
    }
#endif

    float2 randomCouple(float2 coords) {
        float2 v = 0;
#if TEX_NOISE
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        v = (getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rg-0.5)*2;
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);

        v.x = randomValue(seed);
        v.y = randomValue(seed);
#endif
        return v;
    }
    
    
    float3 getRayColor(float2 coords,float2 previousCoords) {
        float3 color = getColor(coords).rgb;
        if(fGIBounce>0.0) {
            color += min(0.5,1.0-getBrightness(color))*getColorSampler(giAccuSampler,previousCoords).rgb*fGIBounce;
        }
        if(fGIDarkAmplify>0) {
            float3 hsv = RGBtoHSV(color);
            hsv.z = saturate(hsv.z+fGIDarkAmplify);
            color = HSVtoRGB(hsv);
        }
        return color;
    }

// PS

    float2 getPreviousCoords(float2 coords) {
        float2 mv = getColorSampler(sTexMotionVectorsSampler,coords).xy;
        return coords+mv;
    }
    

#if ROUGHNESS
    void PS_RoughnessPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRoughness : SV_Target0) {
        if(!bSSR || !bRoughness || fMergingSSR==0.0) discard;
        
        float3 refColor = getColor(coords).rgb;            
        float refB = getBrightness(refColor);
        
        float roughness = 0.0;

        float tempA = 0;
        float tempB = 0;
        
        float3 previousX = refColor;
        float3 previousY = refColor;
        [loop]
        for(int d = 1;d<=iRoughnessRadius;d++) {
            float3 color = getColor(float2(coords.x+ReShade::PixelSize.x*d,coords.y)).rgb;
            float3 diff = previousX-color;
            float r = maxOf3(diff)/safePow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y+ReShade::PixelSize.y*d)).rgb;
            diff = previousY-color;
            r = maxOf3(diff)/safePow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousY = color;
        }
        previousX = refColor;
        previousY = refColor;
        [loop]
        for(int d = 1;d<=iRoughnessRadius;d++) {
            float3 color = getColor(float2(coords.x-ReShade::PixelSize.x*d,coords.y)).rgb;
            float3 diff = previousX-color;
            float r = maxOf3(diff)/safePow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y-ReShade::PixelSize.y*d)).rgb;
            diff = previousY-color;
            r = maxOf3(diff)/safePow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousY = color;
        }
        tempA /= iRoughnessRadius;
        tempA *= sign(tempB);
        roughness = tempA;

        roughness = roughness/2+0.5;

        outRoughness = float4(roughness,roughness,roughness,1.0);
    }
#endif

    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
        
        float3 offset = float3(ReShade::PixelSize, 0.0);
        
        float3 normal = computeNormal(coords,offset);
        
        

        #if NORMAL_FILTER            
            float3 normalTop = computeNormal(coords-offset.zy,offset);
            float3 normalBottom = computeNormal(coords+offset.zy,offset);
            float3 normalLeft = computeNormal(coords-offset.xz,offset);
            float3 normalRight = computeNormal(coords+offset.xz,offset);
            normal += normalTop+normalBottom+normalLeft+normalRight;
            normal/=5.0;
        #endif
        
        outNormal = float4(normal/2.0+0.5,1.0);
        
    }
    
#if GI_PROBE
    float3 getProbeColor(float3 lightVector) {
        float2 probeCoords = 1.0-lightVector.xy;
        return getColorSamplerLod(giProbeSampler,probeCoords,1).rgb;
    }

    void PS_GIProbePass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outProbe : SV_Target0) {
        
        float3 direction = 0;
        direction.xy = 1.0-coords.xy;
        float2 coordsCentered = abs(coords-0.5);
        direction.z = lerp(-1.0,1.0,max(coordsCentered.x,coordsCentered.y)*2);
        
        direction = normalize(direction);
        
        float2 currentCoords;
        float3 currentNormal;
        float3 currentColor;
        float dist;
        
        int steps = 16;
        float2 stepSize = 1.0/(RENDER_SIZE/((steps+1)*2));
        
        float3 sum = 0;
        float weightSum = 0;
        
        float2 offset = (randomCouple(coords)-0.5)/1000;
        
        float weight;
        int2 delta;
        for(delta.x=-steps;delta.x<=steps;delta.x++) {
            for(delta.y=-steps;delta.y<=steps;delta.y++) {
                currentCoords = 0.5+offset+stepSize*delta;
                currentNormal = getNormal(currentCoords);
                
                currentColor = getColor(currentCoords).rgb;
                
                dist = maxOf3(abs(currentNormal-direction));
                weight = 0.1+(1.0-dist);
                weight *= 0.75+getBrightness(currentColor);
                
                sum += weight * currentColor;
                weightSum += weight;
            }
        }
        
        outProbe = float4(weightSum<0.1?0:sum/weightSum,1.0);
        
    }
#endif

    bool checkHit(float minDepth,float rayDepth) {
        return rayDepth>=minDepth;
    }
    
    
    bool crossing(float deltaZbefore, float deltaZ) {
        return (deltaZ<0 && deltaZbefore>0) || (deltaZ>0 && deltaZbefore<0);
    }
    
    float4 trace(float3 refWp,float3 normal,float3 lightVector,float startDepth,bool ssr) {
                
        float stepRatio;
        float stepLength = 1.0/(ssr?50.0:fRayStepPrecision);
        
        float3 incrementVector = lightVector*stepLength;
        if(!ssr) {
            incrementVector *= 1+2000*startDepth;
        }
        
        float traceDistance = 0;
        float3 currentWp = refWp;

        float deltaZ = 0.0;
        float deltaZbefore = 0.0;

        
        float3 lastSky = 0.0;
        
        bool firstStep = true;
        
        bool startWeapon = startDepth<fWeaponDepth;
        float weaponLimit = fWeaponDepth*BUFFER_SIZE3.z;
        
        bool outSource = false;
        
        float distBehind = 0;
            
        float3 screenCoords;
        float3 screenWp;
        
        bool outScreen;
        float depth;
        float ratio;
        
        [loop]
        do {
            currentWp += incrementVector;
            traceDistance += stepLength;
            
            screenCoords = getScreenPosition(currentWp);
            
            outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            
            depth = ReShade::GetLinearizedDepth(screenCoords.xy);
            screenWp = getWorldPosition(screenCoords.xy,depth.x);
            
            deltaZ = screenWp.z-currentWp.z;
            
            if(depth.x>fSkyDepth) {
                lastSky = currentWp;
            }            
            
            if(firstStep && deltaZ<0 && !ssr) {
                return RT_MISSED_FAST;
                
            } else if(outScreen) {
                if(lastSky.x!=0.0) {
                    return float4(lastSky,RT_HIT_SKY);
                }
                    
                currentWp -= incrementVector;
                return RT_MISSED;
                
            } else if(outSource) {
            
                bool crossed = crossing(deltaZbefore,deltaZ);
                
                if(crossed) {
                    
                    float3 subIncVec = incrementVector;
                    currentWp -= incrementVector;
                    [loop]
                    for(int i=0;i<iRTCheckHitPrecision;i++) {
                        subIncVec /= 2;
                        currentWp += subIncVec;
                        
                        screenCoords = getScreenPosition(currentWp);
                        depth = ReShade::GetLinearizedDepth(screenCoords.xy);
                       
                        screenWp = getWorldPosition(screenCoords.xy,depth);
                        deltaZ = screenWp.z-currentWp.z;                        
                        
                        if(crossing(deltaZbefore,deltaZ)) {
                            currentWp -= subIncVec;
                        }
                    }
                    
                    
                    if(bRTHitFast || abs(deltaZ)<=0.1) {
                        return float4(currentWp,RT_HIT+deltaZ);
                    }
                }
                
                
            } else {
                outSource = !checkHit(depth,screenCoords.z+0.001*startDepth);
            }
            
            firstStep = false;
            
            deltaZbefore = deltaZ;
            
            stepRatio = 1.01+depth;
            stepLength *= stepRatio;
            incrementVector *= stepRatio;

        } while(traceDistance<OPTIMIZATION_RT_MAX_DISTANCE*INPUT_WIDTH*2.0*(ssr?1.0:0.001));

        return RT_MISSED;
    }

// GI
    int halfIndex(float2 coords) {
        int2 coordsInt = (coords * RENDER_SIZE)%2;
        return coordsInt.x==coordsInt.y?0:1;
    }
    
    int quadIndex(float2 coords) {
        int2 coordsInt = (coords * RENDER_SIZE)%2;
        return coordsInt.x+coordsInt.y*2;
    }
    
    void getPerpendicularVectors(float3 originalVector, out float3 perpendicularVector1, out float3 perpendicularVector2)
    {
        // Set the first perpendicular vector as the cross product of the original vector and the up vector (0, 1, 0)
        perpendicularVector1 = cross(originalVector, float3(0, 1, 0));
    
        // If the original vector is parallel to the up vector, use the cross product with the right vector (1, 0, 0)
        if (length(perpendicularVector1) < 0.001)
        {
            perpendicularVector1 = cross(originalVector, float3(1, 0, 0));
        }
    
        // Normalize the first perpendicular vector
        perpendicularVector1 = normalize(perpendicularVector1);
    
        // Calculate the second perpendicular vector by taking the cross product of the original vector and the first perpendicular vector
        perpendicularVector2 = cross(originalVector, perpendicularVector1);
        
        // Normalize the second perpendicular vector
        perpendicularVector2 = normalize(perpendicularVector2);
    }
    
    float3 rotateVector(float3 vectorToRotate, float3 axis, float angle) {
        // Normalize the axis vector
        //axis = normalize(axis);
    
        // Calculate sine and cosine of the rotation angle
        float cosTheta;
        float sinTheta;
        sincos(angle,sinTheta,cosTheta);
    
        // Calculate the dot product of the vector to rotate and the axis vector
        float dotProduct = dot(vectorToRotate, axis);
    
        // Calculate the cross product of the vector to rotate and the axis vector
        float3 crossProduct = cross(vectorToRotate, axis);
    
        // Perform the rotation using Rodrigues' rotation formula
        float3 rotatedVector = vectorToRotate * cosTheta + crossProduct * sinTheta + axis * dotProduct * (1 - cosTheta);
    
        return rotatedVector;
    }
    

    
    float3 randomHemispehreVector(float2 coords,float3 normal,float variability) {

        float2 v = (randomCouple(coords)-0.5)*PI;
        v.x*=variability;
        v.y*=2;
        
        float3 per1;
        float3 per2;
        getPerpendicularVectors(normal,per1,per2);
        
        float3 result = rotateVector(normal,per1,v.x);
        result = rotateVector(result,per2,v.y);
        return normalize(result);

    }

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
            outGI = float4(getColor(coords).rgb,1.0);
            return;
        }
        
        float3 refWp = getWorldPosition(coords,depth);
        float3 normal = getNormal(coords);
        
        float2 previousCoords = getPreviousCoords(coords);
        float4 previousFrame = getColorSampler(giAccuSampler,previousCoords);
        
        if(iCheckerboardRT==1 && halfIndex(coords)!=framecount%2) {
            outGI = previousFrame;
            return;
        }
        if(iCheckerboardRT==2 && quadIndex(coords)!=framecount%4) {
            outGI = previousFrame;
            return;
        }
        
        float4 hitPosition;
        float3 screenCoords;
        float3 hitPreviousCoords;
        
        float4 mergedGiColor = 0.0;
        float3 missGiColor = 0.0;
        float mergedAO = 0.0;
        
        int hits = 0;
        int aoHits = 0;

#if !OPTIMIZATION_ONE_LOOP_RT
        int maxRays = iRTMaxRays;
        [loop]
        for(int rays=0;rays<maxRays && maxRays<=iRTMaxRays*OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO && (hits==0||mergedGiColor.a<fRTMinRayBrightness);rays++) {
#else
        int maxRays = 0;
        int rays = 0;
#endif
            float3 lightVector;
            float3 randomVector = randomHemispehreVector(coords+float2(0.1,0.05)*rays,normal,0.9);
            lightVector = randomVector;
            
            hitPosition = trace(refWp,normal,lightVector,depth,false);
            if(RT_MISSED_FAST) {
                maxRays++;
            } 
            
            screenCoords = getScreenPosition(hitPosition.xyz);
            float deltaZ = hitPosition.a-RT_HIT;
            
            float d = distance(hitPosition.xyz,refWp);

            float4 giColor;
            if(hitPosition.a>=0) {
                hits++;
                hitPreviousCoords = getPreviousCoords(screenCoords.xy);
                giColor.rgb = getRayColor(screenCoords.xy,hitPreviousCoords.xy).rgb;
                float b = getBrightness(giColor.rgb);
                
                if(b<0.5) {
                    d/=0.001+b*2;
                } else {
                    d*=(1.0-b);
                }
                giColor.rgb *= saturate(b*1.5*safePow(saturate(1.0-d/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE),fGIDistancePower));                
                
                // Reduce light halo
                giColor.rgb *= saturate(1.0+deltaZ*2);
            } else if(fSkyColor>0 && hitPosition.a==RT_HIT_SKY) {
                giColor.rgb = getColor(screenCoords.xy).rgb*fSkyColor;
            } else if(hitPosition.a<=RT_MISSED) {
                giColor.rgb = 0;
#if GI_PROBE
                missGiColor = max(missGiColor,getProbeColor(normalize(lightVector)));
#else
                missGiColor = previousFrame.rgb;
#endif
            }
            
            giColor.a = getBrightness(giColor.rgb);
            // Use saturation
            giColor.a *= 0.1+getPureness(giColor.rgb);
            
            mergedGiColor = giColor.a>mergedGiColor.a? giColor : mergedGiColor;
            
            if(d<iAODistance*depth && depth>=fWeaponDepth && hitPosition.a>=0) {
                aoHits++;
                float ao = deltaZ<0 ? 1 : 5*d/(iAODistance*depth);
                mergedAO += ao;
            }
                
            
#if !OPTIMIZATION_ONE_LOOP_RT
        }
#endif

        if(hits==0) {
            mergedGiColor.rgb = missGiColor*0.5;            
        }
        if(aoHits==0) {
            mergedAO = 1.0;
        } else {
            mergedAO /= aoHits;
        }
        
        float previousFrameOpacity = 1.0 - 1.0/iFrameAccu;
            
        mergedGiColor.rgb = max(mergedGiColor.rgb,previousFrame.rgb*previousFrameOpacity);    
        mergedAO = max(mergedAO,previousFrame.a*previousFrameOpacity);
        
        outGI = float4(mergedGiColor.rgb,mergedAO);
    }

// SSR
    void PS_SSRLightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!bSSR || fMergingSSR==0.0) {
            outColor = float4(0,0,0,1);
            return;
        }
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
            outColor = float4(0,0,0,1);
        } else {
            
            float3 targetWp = getWorldPosition(coords,depth);
            float3 targetNormal = getNormal(coords);
    
            float3 lightVector = reflect(targetWp,targetNormal)*0.1;
            
            float3 normal = getNormal(coords);
            
#if ROUGHNESS
            if(bRoughness) {
                float3 randomVector;
                float roughness = getRoughness(coords);
                float randomness = saturate(roughness*fRoughnessIntensity*10);
                
                float2 r = randomCouple(coords)-0.5;
                lightVector = rotateVector(lightVector,normal,r.x*randomness);
                lightVector = rotateVector(lightVector,normal,r.y*randomness);
            }
#endif
            //lightVector = normalize(lightVector);
            
            float4 hitPosition = trace(targetWp,normal,lightVector,depth,true);

            float2 previousCoords = getPreviousCoords(coords);
            float3 previousSSR = getColorSampler(ssrAccuSampler,previousCoords).rgb;
                    
            if(hitPosition.a<=RT_MISSED) {
                // no hit
                outColor = float4(previousSSR*0.99,1.0);
                
            } else {
                float3 screenCoords = getScreenPosition(hitPosition.xyz);
                float3 color = getColorSampler(resultSampler,screenCoords.xy).rgb;
                float angle = max(0.25,1.0-dot(normal,normalize(float3(coords-0.5,1))));
                color*=angle;
        
                float opacity = saturate(2.0/iFrameAccu);
                color = lerp(previousSSR,color,opacity);
                
                outColor = float4(color,1.0);
            }
        }
    }
    
    void smooth(
        sampler sourceGISampler,
        sampler sourceSSRSampler,
        float2 coords, out float4 outGI, out float4 outSSR,bool firstPass
    ) {
        
        float refDepth = ReShade::GetLinearizedDepth(coords);
        if(refDepth>fSkyDepth) {
            outGI = float4(0,0,0,1.0);
            outSSR = float4(0,0,0,1);
            return;
        }
        
        float3 refNormal = getNormal(coords);
        
         
        float4 giAo = 0;
        float weightSum = 0;
        
        float3 ssr;
        float ssrWeightSum = 0;
        
        float2 pixelSize = RenderPixelSize();
        
        float2 currentCoords;
        
        int2 delta;
        
        [loop]
        for(delta.x=-iSmoothRadius;delta.x<=iSmoothRadius;delta.x++) {
            [loop]
            for(delta.y=-iSmoothRadius;delta.y<=iSmoothRadius;delta.y++) {
                
                float2 ssrCurrentCoords = coords+delta*pixelSize*(firstPass ? iSmoothSSRStep : 1);
                currentCoords = coords+delta*pixelSize*(firstPass ? iSmoothStep : 1);
                
                float dist = distance(0,delta);
                
                if(dist>iSmoothRadius) continue;
            
                
                float depth = ReShade::GetLinearizedDepth(currentCoords);
                if(depth>fSkyDepth) continue;
                
                float4 curGiAo = getColorSamplerLod(sourceGISampler,currentCoords,firstPass ? (iSmoothStep-1.0)*0.5 : 0.0);
                float3 ssrColor = dist>iSmoothSSRRadius 
                    ? 0
                    : getColorSamplerLod(sourceSSRSampler,ssrCurrentCoords, firstPass ? iSmoothSSRStep*0.5 : 0.0).rgb;
                
                // Distance weight | gi,ao,ssr 
                float weight = safePow(1.0+iSmoothRadius/(dist+1),fSmoothDistPow);             
                
                { // Normal weight
                    float3 normal = getNormal(currentCoords);
                    float3 t = normal-refNormal;
                    float dist2 = max(dot(t,t), 0.0);
                    float nw = min(exp(-(dist2)/(1.0-fNormalWeight)), 1.0);
                    
                    weight *= nw*nw;
                }
                
                { // Depth weight
                    float3 t = depth-refDepth;
                    float dist2 = max(dot(t,t), 0.0);
                    float dw = min(exp(-(dist2)*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE),1.0);                                
                
                    weight *= dw*dw;
                }
                
                if(iCheckerboardRT==1 && halfIndex(currentCoords)==framecount%2) {
                    weight *= 2;
                } else if(iCheckerboardRT==2 && quadIndex(currentCoords)==framecount%4) {
                    weight *= 4;
                }
                 
                giAo += curGiAo*weight;
                weightSum += weight;
                
                if(dist<=iSmoothSSRRadius) {
                    ssr += ssrColor * weight;
                    ssrWeightSum += weight;
                }
                        
            } // end for y
        } // end for x
        
        giAo /= weightSum;
        ssr /= ssrWeightSum;
        
        if(firstPass) {
            float2 previousCoords = getPreviousCoords(coords);        
            float4 previousPass = getColorSampler(giAccuSampler,previousCoords);

            float opacity = 1.0/iFrameAccu;
            outGI = lerp(previousPass,giAo,opacity);
            
            opacity = 1.0/max(2.0,iFrameAccu/2.0);
            float3 previousSSR = getColorSampler(ssrAccuSampler,previousCoords).rgb;
            outSSR = float4(lerp(previousSSR,ssr,opacity),1.0);
        } else {
            outGI = giAo;
            outSSR = float4(ssr,1);
        }

        
        
    }
    
    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {
        smooth(giPassSampler,ssrPassSampler,coords,outGI,outSSR, true);
    }
    
    void PS_AccuPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {
        smooth(giSmoothPassSampler,ssrSmoothPassSampler,coords,outGI,outSSR, false);
    }
    
    float computeColorPreservationGI(float colorBrightness, float giBrightness) {
        return 1.0;
    }
    
    float computeColorPreservationAO(float colorBrightness, float giBrightness) {
        float colorPreservation = 1.0;
        return colorPreservation;
    } 
    
    float computeAo(float ao,float colorBrightness, float giBrightness) {
        ao = lerp(ao,1.0,giBrightness);
        ao = 1.0-safePow(1.0-ao,fAOPow);
        
        ao = saturate(1.0-(1.0-ao)*fAOMultiplier);
        ao = saturate(ao+colorBrightness*fAOLightProtect*2.0);
        ao = saturate(ao+(1.0-colorBrightness)*fAODarkProtect*2.0);        

        return ao;
    }
    
    float3 computeSSR(float2 coords,float brightness) {
        float3 ssr = getColorSampler(ssrAccuSampler,coords).rgb;
        float ssrBrightness = getBrightness(ssr);
        
        float colorPreservation = lerp(1,safePow(brightness,2),1.0-safePow(1.0-brightness,10));
        
        ssr = lerp(ssr,ssr*0.5,ssrBrightness);            
        
#if ROUGHNESS
        float roughness = safePow(getRoughness(coords),2.0);
#else
        float roughness = 0;
        float fMergingRoughness = 0.001;
#endif
        
        float fixedDark = 1.0-safePow(1.0-brightness,fMergingRoughness);
        
        float ssrRatio2 = fixedDark/fMergingRoughness;
        float ssrRatio1 = max(0.0,saturate(1.0-(roughness+0.1))*fMergingRoughness);
        
        return saturate((1.0-saturate(ssrRatio1-ssrRatio2))*ssr*fMergingSSR*(1.0-colorPreservation)*1.5);
            
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outResult : SV_Target) {
        float depth = ReShade::GetLinearizedDepth(coords);
        float3 color = getColor(coords).rgb;
        
        if(depth>fSkyDepth) {
            outResult = float4(color,1.0);
        } else {
            color = saturate(color*fBaseColor);
            float originalColorBrightness = getBrightness(color);
            float colorBrightness = originalColorBrightness;
            float colorPureness = getPureness(color);
            
            float4 passColor = getColorSampler(giAccuSampler,coords);
            
            float3 gi = passColor.rgb;
            float giBrightness =  getBrightness(gi);
            float giPureness = getPureness(gi);
            
            // Apply AO
            float ao = passColor.a;
            ao = computeAo(ao,colorBrightness,giBrightness);
            color *= ao;
            colorBrightness = getBrightness(color);
            colorPureness = getPureness(color);
            
            // Base color
            float3 result = color;
            
            // GI
            
            // Dark areas
            float darkMerging = fGIDarkMerging;
            if(bGIHDR) {
                float avg = getBrightness(getColorSamplerLod(giSmoothPassSampler,float2(0.5,0.5),9.0).rgb);
                darkMerging *= 1.0-avg/2.0;
            }
            result += lerp(0,(result+0.1)*gi,(1.0-colorBrightness)*darkMerging*2.0);
            
            // Light areas
            result = result*fGILightMerging+lerp(result,(result+0.2)*gi,giBrightness*saturate(1.5-colorPureness)*colorBrightness*fGILightMerging);
            
            // Mixing
            float colorPreservation = saturate(safePow(colorBrightness*2.0-1.0,10*fGIFinalMerging));
            result = lerp(result,color,colorPreservation);
            
            // SSR
            if(bSSR && fMergingSSR>0.0) {
                float3 ssr = computeSSR(coords,colorBrightness);
                result += ssr;
            }
            
            // Levels
            result = (result-iBlackLevel/255.0)/((iWhiteLevel-iBlackLevel)/255.0);
            
            // Distance fading
            if(fDistanceFading<1.0 && depth>fDistanceFading) {
                float diff = depth-fDistanceFading;
                float max = 1.0-fDistanceFading;
                float ratio = diff/max;
                result = result*(1.0-ratio)+color*ratio;
            }
          
            
            outResult = float4(result,1);
        }
    }
    

    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
    {        
        float3 result = 0;
        
        if(iDebug==DEBUG_OFF) {
            result = getColorSampler(resultSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_GI) {
            float4 passColor =  getColorSampler(giAccuSampler,coords);
            float3 gi =  passColor.rgb;
            
            result = gi;
            
        } else if(iDebug==DEBUG_AO) {
            float4 passColor =  getColorSampler(giAccuSampler,coords);
            float3 gi =  passColor.rgb;
            float giBrightness = getBrightness(gi);
            
            float3 color = getColor(coords).rgb;
            float colorBrightness = getBrightness(color);
            
            float ao = passColor.a;
            ao = computeAo(ao,colorBrightness,giBrightness);
            
            
            result = ao;
            
        } else if(iDebug==DEBUG_SSR) {
            float3 color = getColor(coords).rgb;       

            result = computeSSR(coords,getBrightness(color))*1.5;
            
        } else if(iDebug==DEBUG_ROUGHNESS) {
#if ROUGHNESS
            result = getColorSampler(roughnessSampler,coords).rgb;
#endif
        } else if(iDebug==DEBUG_DEPTH) {
            result = ReShade::GetLinearizedDepth(coords);
            
        } else if(iDebug==DEBUG_NORMAL) {
            result = getColorSampler(normalSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_SKY) {
            float depth = ReShade::GetLinearizedDepth(coords);
            result = depth>fSkyDepth?1.0:0.0;
      
        } else if(iDebug==DEBUG_MOTION) {
            float2  motion = getPreviousCoords(coords);
            motion = (motion-coords)*50;
            result = float3(motion,0);
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT {
#if ROUGHNESS
        // Normal Roughness
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RoughnessPass;
            RenderTarget = roughnessTex;
        }
#endif

        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_NormalPass;
            RenderTarget = normalTex;
        }

        // GI
#if GI_PROBE
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_GIProbePass;
            RenderTarget = giProbeTex;
        }
#endif
        
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_GILightPass;
            RenderTarget = giPassTex;
        }
        
        // SSR
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SSRLightPass;
            RenderTarget = ssrPassTex;
            
            ClearRenderTargets = false;
                        
            BlendEnable = true;
            BlendOp = ADD;
            SrcBlend = SRCALPHA;
            SrcBlendAlpha = ONE;
            DestBlend = INVSRCALPHA;
            DestBlendAlpha = ONE;
        }
        
        // Denoising
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothPass;
            RenderTarget = giSmoothPassTex;
            RenderTarget1 = ssrSmoothPassTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_AccuPass;
            RenderTarget = giAccuTex;
            RenderTarget1 = ssrAccuTex;
        }
        
        // Merging
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateResult;
            RenderTarget = resultTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }
}