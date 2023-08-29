////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT 0.15.0 (2023-08-30)
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://alucarddh.github.io
// Join my Discord server for news, request, bug reports or help : https://discord.gg/V9HgyBRgMW
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

// HIDDEN PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////
// Should not be modified but can help if you really want to squeeze some FPS at the cost of lower fidelity

// Define the maximum distance a ray can travel
// Default is 1.0 : the full screen/depth, less (0.5) can be enough depending on the game
#ifndef OPTIMIZATION_RT_MAX_DISTANCE
    #define OPTIMIZATION_RT_MAX_DISTANCE 1.0
#endif

#define OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO 3

#define OPTIMIZATION_RT_DETAILS_RADIUS 2

// Define is the roughness is actived
// Default is 1 (activated), can be deactivated
#define ROUGHNESS 1

// Define is a light smoothing filter on Normal
// Default is 1 (activated)
#define NORMAL_FILTER 1

// Enable ambient light functionality
// Default is 1 (activated)
#define AMBIENT_ON 1

#define DX9_MODE (__RENDERER__==0x9000)

#define TEX_NOISE DX9_MODE
#define OPTIMIZATION_ONE_LOOP_RT DX9_MODE


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
#define DEBUG_AMBIENT 9

#define RT_HIT 1.0
#define RT_HIT_SKY -0.5
#define RT_MISSED -1.0
#define RT_MISSED_FAST -2.0

#define PI 3.14159265359
#define SQRT2 1.41421356237

#define fGIDistancePower 2.0

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
#define getNormal(c) (tex2Dlod(normalSampler,float4((c).xy,0,0)).xyz-0.5)*2
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4((c).xy,0,0))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4((c).xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4((c).xy,0,0))
#define maxOf3(a) max(max(a.x,a.y),a.z)
#define minOf3(a) min(min(a.x,a.y),a.z)
#define avgOf3(a) (((a).x+(a).y+(a).z)/3.0)
#define getBrightness(color) maxOf3((color))
#define getPureness(color) (maxOf3((color))-minOf3((color)))
#define CENTER float2(0.5,0.5)
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
#if AMBIENT_ON
    texture ambientTex { Width = 1; Height = 1; Format = RGBA16F; };
    sampler ambientSampler { Texture = ambientTex; };   

    texture previousAmbientTex { Width = 1; Height = 1; Format = RGBA16F; };
    sampler previousAmbientSampler { Texture = previousAmbientTex; }; 
#endif

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
    texture rayColorTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler rayColorSampler { Texture = rayColorTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giPassSampler { Texture = giPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler giAccuSampler { Texture = giAccuTex; };

    // SSR textures
#if ROUGHNESS
    texture roughnessTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler roughnessSampler { Texture = roughnessTex; };
#endif
    
    texture ssrPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA32F; };
    sampler ssrPassSampler { Texture = ssrPassTex; };

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
        ui_min = 0; ui_max = 64;
        ui_step = 1;
    > = 1;
    uniform bool bTest2 = true;
    uniform bool bTest3 = true;
    uniform bool bTest4 = true;
*/
    
    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0GI\0AO\0SSR\0Roughness\0Depth\0Normal\0Sky\0Motion\0Ambient light\0";
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
    uniform bool bRTHitFast <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Opti Fast hit";
        ui_tooltip = "Simplify hit detection to get more performances";
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
    > = 4;
    
#if DX9_MODE
#else
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
#endif

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
    > = 6;
    
    uniform float fRayStepPrecision <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Step Precision";
        ui_min = 100.0; ui_max = 2000;
        ui_step = 0.1;
        ui_tooltip = "Define the length of the steps during ray tracing.\n"
                    "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES";
    > = 1000.0;

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
    > = 2;
    
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

#if ROUGHNESS
    uniform float fNormalRoughness <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Normal roughness";
        ui_min = 0.000; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.15;
#endif

// AMBIENT LIGHT 
#if AMBIENT_ON
    uniform bool bRemoveAmbient <
        ui_category = "Ambient light";
        ui_label = "Remove Source Ambient light";
    > = true;
    
    uniform bool bRemoveAmbientAuto <
        ui_category = "Ambient light";
        ui_label = "Auto ambient color";
    > = true;

    uniform float3 cSourceAmbientLightColor <
        ui_type = "color";
        ui_category = "Ambient light";
        ui_label = "Source Ambient light color";
    > = float3(31.0,44.0,42.0)/255.0;
    
    uniform float fSourceAmbientIntensity <
        ui_type = "slider";
        ui_category = "Ambient light";
        ui_label = "Strength";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
    > = 1.0;
    
    uniform bool bRemoveAmbientPreserveBrightness <
        ui_category = "Ambient light";
        ui_label = "Preserve brighthness";
    > = false;
    
    uniform int iRemoveAmbientMode <
        ui_category = "Ambient light";
        ui_label = "Mode";
        ui_type = "combo";
        ui_items = "As external\0Only GI\0Only base image\0";
    > = 0;
    
/// ADD
    uniform bool bAddAmbient <
        ui_category = "Ambient light";
        ui_label = "Add Ambient light";
    > = false;

    uniform float3 cTargetAmbientLightColor <
        ui_type = "color";
        ui_category = "Add ambient light";
        ui_label = "Target Ambient light color";
    > = float3(13.0,13.0,13.0)/255.0;
#endif
    
// GI
    
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
    > = 0.10;
    
    uniform float fGIBounce <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Bounce intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define if GI bounces in following frames";
    > = 0.25;

    uniform float fGIHueBiais <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Hue Biais";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much base color can take GI hue.";
    > = 0.25;
    
        
    uniform float fGILightMerging <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "In Light intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much bright areas are affected by GI.";
    > = 0.50;
    uniform float fGIDarkMerging <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "In Dark intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much dark areas are affected by GI.";
    > = 0.50;
    
    uniform float fGIFinalMerging <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "General intensity";
        ui_min = 0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the whole image is affected by GI.";
    > = 1.0;
    
    uniform bool bGIHDR <
        ui_category = "GI";
        ui_label = "GI Dynamic dark";
        ui_tooltip = "Enable to adapt GI in the dark relative to screen average brigthness.";
    > = true;
    
// AO

    uniform bool bAoNew <
        ui_category = "AO";
        ui_label = "New AO method";
    > = true;
    
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
    > = BUFFER_WIDTH/4;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Pow";
        ui_min = 0.001; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 1.5;
    
    uniform float fAOLightProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Light protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of bright areas to avoid washed out highlights";
    > = 0.40;
    
    uniform float fAODarkProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Dark protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of dark areas to avoid totally black and unplayable parts";
    > = 0.10;

    uniform float fAoProtectGi <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "GI protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.5;
    


    // SSR
    uniform bool bSSR <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Enable SSR";
        ui_tooltip = "Toggle SSR";
    > = false;
    
#if ROUGHNESS
    uniform int iRoughnessRadius <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness Radius";
        ui_min = 1; ui_max = 4;
        ui_step = 2;
        ui_tooltip = "Define the max distance of roughness computation.\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    
    uniform float fMergingRoughness <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness reflexivity";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define how much the roughness decrease reflection intensity";
    > = 1.0;
#endif

    uniform float fMergingSSR <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "SSR Intensity";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define this intensity of the Screan Space Reflection.";
    > = 0.25;

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
    > = 1.0;

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
    
#if ROUGHNESS
    bool isRoughnessEnabled() {
        return fNormalRoughness>0 || bSSR;
    }
    
    float getRoughness(float2 coords) {
        if(!isRoughnessEnabled()) {
            return 0;
        }
        return getColorSampler(roughnessSampler,coords).r;
    }
    
#else
    bool isRoughnessEnabled() {
        return false;
    }
    
    float getRoughness(float2 coords) {
        return 0;
    }
#endif
    
    float3 getWorldPositionForNormal(float2 coords) {
        float depth = ReShade::GetLinearizedDepth(coords);
        if(fNormalRoughness>0) {
            float r = getRoughness(coords);
            depth += r*(depth)*fNormalRoughness*0.1;
        }
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
        v = abs((getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rg-0.5)*2.0);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);

        v.x = randomValue(seed);
        v.y = randomValue(seed);
#endif
        return v;
    }
    
    float3 randomTriple(float2 coords) {
        float3 v = 0;
#if TEX_NOISE
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        v = abs((getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rgb-0.5)*2.0);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);

        v.x = randomValue(seed);
        v.y = randomValue(seed);
        v.z = randomValue(seed);
#endif
        return v;
    }
    
    float3 getRayColor(float2 coords) {
        return getColorSampler(rayColorSampler,coords).rgb;
    }
    
    bool isEmpty(float3 v) {
        return maxOf3(v)==0;
    }

// PS

    float2 getPreviousCoords(float2 coords) {
        float2 mv = getColorSampler(sTexMotionVectorsSampler,coords).xy;
        return coords+mv;
    }
    

#if ROUGHNESS
    void PS_RoughnessPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRoughness : SV_Target0) {
        if(!isRoughnessEnabled()) discard;
        
        float3 refColor = getColor(coords).rgb;
        
        float roughness = 0.0;
        float ws = 0;
            
        float3 previousX = refColor;
        float3 previousY = refColor;
        [loop]
        for(int d = 1;d<=iRoughnessRadius;d++) {
            float w = 1.0/safePow(d,0.5);
            
            float3 color = getColor(float2(coords.x+ReShade::PixelSize.x*d,coords.y)).rgb;
            float3 diff = abs(previousX-color);
            roughness += maxOf3(diff)*w;
            ws += w;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y+ReShade::PixelSize.y*d)).rgb;
            diff = abs(previousY-color);
            roughness += maxOf3(diff)*w;
            ws += w;
            previousY = color;
        }
        previousX = refColor;
        previousY = refColor;
        [loop]
        for(int d = 1;d<=iRoughnessRadius;d++) {
            float w = 1.0/safePow(d,0.5);
            
            float3 color = getColor(float2(coords.x-ReShade::PixelSize.x*d,coords.y)).rgb;
            float3 diff = abs(previousX-color);
            roughness += maxOf3(diff)*w;
            ws += w;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y-ReShade::PixelSize.y*d)).rgb;
            diff = abs(previousY-color);
            roughness += maxOf3(diff)*w;
            ws += w;
            previousY = color;
        }
        
        
        roughness *= 4.0/iRoughnessRadius;
  
        float refB = getBrightness(refColor);      
        roughness *= safePow(refB,0.5);
        roughness *= safePow(1.0-refB,2.0);
        
        outRoughness = float4(roughness,roughness,roughness,1.0);
    }
#endif

#if AMBIENT_ON
    void PS_SavePreviousAmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {
        outAmbient = getColorSampler(ambientSampler,CENTER);
    }
    
    void PS_AmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {
        if(!bRemoveAmbient || !bRemoveAmbientAuto) discard;

        float3 previous = getColorSampler(previousAmbientSampler,CENTER).rgb;
        float3 result = previous;
        float b = getBrightness(result);
        bool first = false;
        if(b==0) {
            result = 1.0;
            first = true;
        }
        if(framecount%60==0) {
            result = 1.0;
        }
        
        float bestB = b;
        
        float2 currentCoords = 0;
        float2 bestCoords = CENTER;
        float2 rand = randomCouple(coords);
        
        float2 size = BUFFER_SIZE;
        float stepSize = BUFFER_WIDTH/16.0;
        float2 numSteps = size/(stepSize+1);
        
            
        //float2 rand = randomCouple(currentCoords);
        for(int it=0;it<=4 && stepSize>=1;it++) {
            float2 stepDim = stepSize/BUFFER_SIZE;
        
            for(currentCoords.x=bestCoords.x-stepDim.x*(numSteps.x/2);currentCoords.x<=bestCoords.x+stepDim.x*(numSteps.x/2);currentCoords.x+=stepDim.x) {
                for(currentCoords.y=bestCoords.y-stepDim.y*(numSteps.y/2);currentCoords.y<=bestCoords.y+stepDim.y*(numSteps.y/2);currentCoords.y+=stepDim.y) {
                    float3 color = getColor(currentCoords+rand*stepDim).rgb;
                    b = getBrightness(color);
                    if(b>0.1 && b<bestB) {
                        result = min(result,color);
                        bestB = b;
                    }
                }
            }
            size = stepSize;
            numSteps = 8;
            stepSize = size.x/8;
        }
        
        float opacity = b==1 ? 0 : (0.01+getPureness(result))*0.5;
        outAmbient = float4(result,first ? 1 : opacity);
        
    }
    
    float3 getRemovedAmbiantColor() {
        if(bRemoveAmbientAuto) {
            float3 color = getColorSampler(ambientSampler,float2(0.5,0.5)).rgb;
            color += getBrightness(color);
            return color;
        } else {
            return cSourceAmbientLightColor;
        }
    }
    
    float3 filterAmbiantLight(float3 sourceColor) {
        float3 color = sourceColor;
        if(bRemoveAmbient) {
            float3 colorHSV = RGBtoHSV(color);
            float3 ral = getRemovedAmbiantColor();
            float3 removedTint = ral - minOf3(ral); 
            float3 sourceTint = color - minOf3(color);
            
            float hueDist = maxOf3(abs(removedTint-sourceTint));
            
            float removal = saturate(1.0-hueDist*saturate(colorHSV.y+colorHSV.z));
         color -= removedTint*removal;
            color = saturate(color);
            
            if(bRemoveAmbientPreserveBrightness) {
                float sB = getBrightness(sourceColor);
                float nB = getBrightness(color);
                
                color += sB-nB;
            }
            
            color = lerp(sourceColor,color,fSourceAmbientIntensity);
            
            if(bAddAmbient) {
                float b = getBrightness(color);
                color = saturate(color+pow(1.0-b,4.0)*cTargetAmbientLightColor);
            }
        }
        return color;
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
    
    void PS_RayColorPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        
        float refDepth = ReShade::GetLinearizedDepth(coords);
        
        float2 previousCoords = getPreviousCoords(coords);
        float2 previousDelta = coords-previousCoords;
        
        float3 result = 0;
    
        float maxScore = -1;
        float resultCount = 0;
        int2 delta;
        
        for(delta.x=-OPTIMIZATION_RT_DETAILS_RADIUS;delta.x<=OPTIMIZATION_RT_DETAILS_RADIUS;delta.x++) {
            for(delta.y=-OPTIMIZATION_RT_DETAILS_RADIUS+abs(delta.x);delta.y<=OPTIMIZATION_RT_DETAILS_RADIUS-abs(delta.x);delta.y++) {
                float2 currentCoords = coords+delta*2*ReShade::PixelSize;
                float depth = ReShade::GetLinearizedDepth(currentCoords);
                float depthDiff = abs(depth-refDepth);
                if(depthDiff<=0.1*refDepth) {
                    float3 color = getColor(currentCoords).rgb;
#if AMBIENT_ON
                    if(iRemoveAmbientMode<2) {  
                        color = filterAmbiantLight(color);
                    }
#endif         
                    float b = getBrightness(color);
                    float p = getPureness(color);                    
                    
                    float score = (getPureness(color)+safePow(b,3.0))*(b==1 && p==0?0:1);

                    if(score>maxScore) {
                        result = color;
                        maxScore = score;
                        resultCount = 1.0;
                    }
                }
            }
        }
        result /= resultCount;
        
        if(fGIBounce>0.0) {
            result += min(0.5,1.0-getBrightness(result))*getColorSampler(giAccuSampler,previousCoords).rgb*fGIBounce;
        }
        
        outColor = float4(saturate(result),1.0);
        
    }

    bool hittingSSR(float deltaZ, float maxDeltaZ) {
        return (deltaZ>=0 && deltaZ<=maxDeltaZ) || (deltaZ<=0 && -deltaZ<=maxDeltaZ);
    }
    
    bool hittingGI(float3 screenWp, float3 currentWp, float maxDeltaZ) {
        return distance(screenWp,currentWp)<=maxDeltaZ;
    }
    
    bool crossing(float deltaZbefore, float deltaZ) {
        return  (deltaZ<=0 && deltaZbefore>=0) || (deltaZ>=0 && deltaZbefore<=0);
    }
    
    float4 trace(float3 refWp,float3 incrementVector,float startDepth,bool ssr,bool ssr2) {
                
        float stepRatio;
        float stepLength = 1.0/fRayStepPrecision;
        
        if(!ssr) stepLength *= 0.5;
        
        incrementVector *= stepLength;
        
        incrementVector *= 1+2000*startDepth;
        
        float traceDistance = 0;
        float3 currentWp = refWp;
        
        float3 refNormal = getNormal(getScreenPosition(currentWp).xy);

        float deltaZ = 0.0;
        float deltaZbefore = 0.0;

        
        float3 lastSky = 0.0;
        
        
        bool startWeapon = startDepth<fWeaponDepth;
        float weaponLimit = fWeaponDepth*BUFFER_SIZE3.z;
        
        bool outSource = false;
        
        bool firstStep = true;
        [loop]
        do {
            currentWp += incrementVector;
            traceDistance += stepLength;
            
            float3 screenCoords = getScreenPosition(currentWp);
            
            bool outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            
            float depth = ReShade::GetLinearizedDepth(screenCoords.xy);
            float3 screenWp = getWorldPosition(screenCoords.xy,depth);
            
            deltaZ = screenWp.z-currentWp.z;
            
            if(depth>fSkyDepth) {
                lastSky = currentWp;
            }            
            
            if(outScreen || (firstStep && deltaZ<0 && !ssr)) {
                return RT_MISSED_FAST;
                
            } else {
                outSource = !firstStep && abs(deltaZ)>deltaZbefore;
            }
            
            if(firstStep) deltaZbefore = abs(deltaZ);
            firstStep = false;
            
            

            float2 r = randomCouple(screenCoords.xy);
            stepRatio = 1.00+depth+r.x;
            
            stepLength *= stepRatio;
            incrementVector *= stepRatio;

        } while(!outSource);
        
        deltaZbefore = deltaZ;
        
        float maxDeltaZ = max(0.1,1.0/iRTCheckHitPrecision);
        float3 crossedWp = 0;
        
        if(!ssr) stepLength *= 2.0;
        
        [loop]
        do {
            currentWp += incrementVector;
            traceDistance += stepLength;
            
            float3 screenCoords = getScreenPosition(currentWp);
            
            bool outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            
            float depth = ReShade::GetLinearizedDepth(screenCoords.xy);
            float3 screenWp = getWorldPosition(screenCoords.xy,depth);
            
            deltaZ = screenWp.z-currentWp.z;
            
            if(depth.x>fSkyDepth) {
                lastSky = currentWp;
            }            
            
            if(outScreen) {
                if(lastSky.x!=0.0) {
                    return float4(lastSky,RT_HIT_SKY);
                }
             
                return float4(crossedWp,RT_MISSED);

            } else {
            
                bool crossed = crossing(deltaZbefore,deltaZ);
                if(crossed) {
                    bool hit = false;                   
                        
                    currentWp -= incrementVector;

                    float3 subIncVec = incrementVector;
                    
                    [loop]
                    for(int i=0;!hit && i<iRTCheckHitPrecision;i++) {
                        subIncVec *= 0.5;
                        currentWp += subIncVec;
                        
                        float3 screenCoords = getScreenPosition(currentWp);
                        float depth = ReShade::GetLinearizedDepth(screenCoords.xy);
                       
                        screenWp = getWorldPosition(screenCoords.xy,depth);
                        deltaZ = screenWp.z-currentWp.z;  
                        hit = ssr
                            ? hittingSSR(deltaZ,maxDeltaZ)
                            : hittingGI(screenWp,currentWp,traceDistance*10);
                            
                        if(!hit && abs(subIncVec.x)<1 && abs(subIncVec.y)<1) {
                            currentWp += 0.8*subIncVec*(deltaZ)/subIncVec.z;
                            hit = true;
                        }
                        
                        if(!hit && crossing(deltaZbefore,deltaZ)) {
                            currentWp -= subIncVec;
                        }
                    }
   
                    if(hit || ssr2 || (!ssr && bRTHitFast)) {
                        return float4(currentWp,RT_HIT+(!ssr && deltaZ<0?deltaZ+16/iRTCheckHitPrecision:deltaZ));
                    } else if(maxOf3(abs(crossedWp))==0){
                        crossedWp = currentWp-subIncVec;
                    }
                    
                    // Stop when vector smaller than 1px
                    float3 a = abs(subIncVec);
                    if(a.x<1 && a.y<1) break;   
                }             
                
            }
            
            deltaZbefore = deltaZ;

            float2 r = randomCouple(screenCoords.xy);
            stepRatio = 1.00+depth+r.x;
            
            stepLength *= stepRatio;
            incrementVector *= stepRatio;

        } while(traceDistance<OPTIMIZATION_RT_MAX_DISTANCE*INPUT_WIDTH*0.0005);

        return float4(crossedWp,RT_MISSED);
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

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
            outGI = float4(0.0,0.0,0.0,1.0);
            return;
        }
        
        float3 refWp = getWorldPosition(coords,depth);
        float3 refNormal = getNormal(coords);
        
#if DX9_MODE
        // No checkerboard rendering on DX9 for now
#else
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
#endif

        float4 hitPosition;
        float3 screenCoords;
        
        float3 mergedGiColor = 0.0;
        float mergedAO = 0.0;
        
        float hits = 0;
        float aoHits = 0;
        float aoHitsNew = 0;

#if !OPTIMIZATION_ONE_LOOP_RT
        int maxRays = iRTMaxRays;
        [loop]
        for(int rays=0;rays<maxRays && maxRays<=iRTMaxRays*OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO && (hits==0||getBrightness(mergedGiColor)<fRTMinRayBrightness);rays++) {
#else
        int maxRays = 0;
        int rays = 0;
#endif
            float3 lightVector = normalize(randomTriple(coords+float2(0.1,0.05)*rays)-0.5);
            
            hitPosition = trace(refWp,lightVector,depth,false,false);
            if(hitPosition.a == RT_MISSED_FAST) {
                maxRays++;
#if !OPTIMIZATION_ONE_LOOP_RT
                continue;
#endif
            }
            
            screenCoords = getScreenPosition(hitPosition.xyz);
            
            
            float3 giColor = 0.0;  
            if(hitPosition.a==RT_HIT_SKY) {
                giColor = getColor(screenCoords.xy).rgb*fSkyColor;
            } else if(hitPosition.a>=0 || (maxOf3(abs(hitPosition.rgb))>0)) {
                hits+=1.0;
                giColor = getRayColor(screenCoords.xy).rgb;
                
                float b = getBrightness(giColor);
                float p = getPureness(giColor);
                float3 hsv = RGBtoHSV(giColor);
                hsv.y += p*b*0.25*(0.5+p);
                hsv.z += b*0.5*(0.5+p);
                giColor = HSVtoRGB(hsv);

                // Light hit orientation
                float orientationSource = dot(lightVector,-refNormal);
                giColor *= saturate(0.25+saturate(orientationSource)*4);
                
                float3 normal = getNormal(screenCoords.xy);
                float orientationTarget = dot(lightVector,normal);
                giColor *= saturate(0.5+saturate(orientationTarget)*3);
                
                float3 screenWp = getWorldPosition(screenCoords.xy,ReShade::GetLinearizedDepth(screenCoords.xy));
                float d = distance(screenWp,refWp);
                if(d<iAODistance*depth && depth>=fWeaponDepth && hitPosition.a>=0) {
                    aoHits += 1;
                    float ao = d/(iAODistance*depth);
                    aoHitsNew += 1.0-saturate(ao);
                    ao -= 0.5-smoothstep(-1,1,orientationTarget);
                    mergedAO += saturate(ao);
                }
                
            }
            
            mergedGiColor = max(giColor,mergedGiColor);                
            
#if !OPTIMIZATION_ONE_LOOP_RT
        }
#endif

        if(aoHits==0) {
            mergedAO = 1.0;
        } else {
            if(bAoNew) mergedAO = 1.0-aoHitsNew/hits;
            else mergedAO /= aoHits;
        }
        
        if(fGIDarkAmplify>0) {
            float3 hsv = RGBtoHSV(mergedGiColor);
            hsv.z = saturate(hsv.z+fGIDarkAmplify);
            mergedGiColor = HSVtoRGB(hsv);
        }
        
        float opacity = 1.0/iFrameAccu;

#if DX9_MODE
        float2 previousCoords = getPreviousCoords(coords);
        float4 previousFrame = getColorSampler(giAccuSampler,previousCoords);
#endif

        mergedGiColor = max(mergedGiColor,previousFrame.rgb*max(0.9,1.0-opacity));
        mergedAO = lerp(previousFrame.a,mergedAO,opacity);
        
        outGI = float4(mergedGiColor,mergedAO);
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
            
            
            float angleH = abs(dot(targetNormal,normalize(targetWp)));
            
            float opacity = 1;
            
            float4 hitPosition = trace(targetWp,lightVector,depth,true,false);
            
            if(isEmpty(hitPosition.xyz)) {
                outColor = 0.0;
            } else {
                outColor = float4(getScreenPosition(hitPosition.xyz),hitPosition.a==RT_MISSED ? 0.5 : 1);
            }
        }
            
    }
    
    void smooth(
        sampler sourceGISampler,
        sampler sourceSSRSampler,
        float2 coords, out float4 outGI, out float4 outSSR,bool firstPass
    ) {
        float3 pixelSize = float3(1.0/tex2Dsize(sourceGISampler),0);
        
        float refDepth = ReShade::GetLinearizedDepth(coords);
        if(refDepth>fSkyDepth) {
            outGI = float4(0,0,0,1.0);
            outSSR = float4(0,0,0,1);
            return;
        }
        
        float3 refNormal = getNormal(coords);        
         
        float4 giAo = 0;
        float4 ssr;
        
        float3 weightSum; // gi, ao, ssr
        
        float roughness = getRoughness(coords);
        
        
        float2 currentCoords;
        
        int2 delta;
        
        [loop]
        for(delta.x=-iSmoothRadius;delta.x<=iSmoothRadius;delta.x++) {
            [loop]
            for(delta.y=-iSmoothRadius;delta.y<=iSmoothRadius;delta.y++) {
                
                currentCoords = coords+delta*pixelSize.xy*(firstPass ? iSmoothStep : 1);
                
                float dist = distance(0,delta);
                
                if(dist>iSmoothRadius) continue;
            
                
                float depth = ReShade::GetLinearizedDepth(currentCoords);
                if(depth>fSkyDepth) continue;
                
                float colorMul = 1;
                
                // Distance weight | gi,ao,ssr 
                float3 weight = safePow(1.0+iSmoothRadius/(dist+1),3.0);
                weight.z = safePow(1.0+iSmoothRadius/(dist+1),8.0);
                
                { // Normal weight
                    float3 normal = getNormal(currentCoords);
                    float diffNorm = dot(normal,refNormal);
                    float nw1 = saturate(diffNorm);
                    
                    
                    float3 t = normal-refNormal;
                    diffNorm = length(t);
                    float dist2 = max(dot(t,t), 0.0);
                    float nw2 = min(exp(-(dist2)/(1.0-saturate(diffNorm*10))), 1.0);
                    nw2 *= nw2;
                    
                    weight *= lerp(nw1,nw2,saturate(roughness*5.0));
                }
                
                { // Depth weight
                    float t = (1.0-refDepth)*abs(depth-refDepth);
                    float dw = saturate(0.007-t);
                    
                    weight *= dw;
                }
                
#if DX9_MODE
#else
                if(iCheckerboardRT==1 && halfIndex(currentCoords)==framecount%2) {
                    weight *= 2;
                } else if(iCheckerboardRT==2 && quadIndex(currentCoords)==framecount%4) {
                    weight *= 4;
                }
#endif    
                
                float4 curGiAo = getColorSamplerLod(sourceGISampler,currentCoords,firstPass ? log2(iSmoothStep) : 0.0);
                giAo.rgb += curGiAo.rgb*weight.x*colorMul;
                giAo.a += curGiAo.a*weight.y;
                
                
                if(bSSR) {
                    currentCoords = coords+delta*pixelSize.xy;
                    float4 ssrColor = getColorSampler(sourceSSRSampler,currentCoords);
                    
                    if(firstPass) {
                        weight.z *= ssrColor.a;
                    }
                    
                    ssr += ssrColor * weight.z;
                }
                
                weightSum += weight;
                
                        
            } // end for y
        } // end for x
        
        giAo.rgb /= weightSum.x;
        giAo.a /= weightSum.y;
        ssr /= weightSum.z;
        
        if(firstPass) {
            float2 previousCoords = getPreviousCoords(coords);        
            float4 previousPass = getColorSampler(giAccuSampler,previousCoords);

            float opacity = 1.0/iFrameAccu;
            outGI = lerp(previousPass,giAo,opacity);
            
            if(bSSR) {
                previousPass = getColorSampler(ssrAccuSampler,previousCoords);
                    
                if(maxOf3(ssr.rgb)>0) {
                
                    float3 stableColor = getColor(ssr.xy).rgb;
                                        
                    ssr.xy = getPreviousCoords(ssr.xy);
                    float3 previousColor = getColorSampler(resultSampler,ssr.xy).rgb;                   
                    
                    outSSR = float4(lerp(previousPass.rgb,previousColor,opacity),1);//float4(lerp(previousPass.rgb,ssr.rgb,0.001+saturate(opacity-ssr.a*0.1)),1.0);  
                } else {
                    outSSR = float4(previousPass.rgb*0.99,0.5);
                }
            } else {
                outSSR = 0;
            }
        } else {
            outGI = giAo;
            outSSR = ssr;
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
        ao = lerp(ao,1.0,giBrightness*fAoProtectGi);
        ao = safePow(ao,fAOPow);
        ao = 1.0-(1.0-ao)*fAOMultiplier;
        
        float lightAo = lerp(ao,1.0,saturate(colorBrightness*fAOLightProtect*2.0)); 
        float darkAo = lerp(ao,1.0,saturate((1.0-colorBrightness)*fAODarkProtect*2.0));
        ao = max(lightAo,darkAo);
        
        return saturate(ao);
    }
    
    float3 computeSSR(float2 coords,float brightness) {
        float4 ssr = getColorSampler(ssrAccuSampler,coords);
        if(ssr.a==0) return 0;
        
        float ssrBrightness = getBrightness(ssr);
        float ssrPureness = getPureness(ssr);
        
        float colorPreservation = lerp(1,safePow(brightness,2),1.0-safePow(1.0-brightness,10));
        
        ssr = lerp(ssr,ssr*0.5,saturate(ssrBrightness-ssrPureness));
        
#if ROUGHNESS
        float roughness = safePow(getRoughness(coords),2.0);
#else
        float roughness = 0;
        float fMergingRoughness = 0.001;
#endif
        
        float fixedDark = 1.0-safePow(1.0-brightness,2.0);
        
        float ssrRatio2 = fixedDark/fMergingRoughness;
        float ssrRatio1 = max(0.0,saturate(1.0-(roughness+0.1))*fMergingRoughness);
        
        return saturate((1.0-saturate(ssrRatio1-ssrRatio2))*ssr.rgb*fMergingSSR*(1.0-colorPreservation)*1.5);
            
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outResult : SV_Target) {
        float depth = ReShade::GetLinearizedDepth(coords);
        float3 color = getColor(coords).rgb;
        
        if(depth>fSkyDepth) {
            outResult = float4(color,1.0);
        } else {
            float originalColorBrightness = getBrightness(color);
#if AMBIENT_ON
            if(iRemoveAmbientMode==0 || iRemoveAmbientMode==2) {
                color = filterAmbiantLight(color);
            }
#endif
            
            color = saturate(color*fBaseColor);
            float colorBrightness = originalColorBrightness;
            float colorPureness = getPureness(color);
            
            
            float4 passColor = getColorSampler(giAccuSampler,coords);
            
            float3 gi = passColor.rgb;
            float giBrightness =  getBrightness(gi);
            float giPureness = getPureness(gi);
            
            colorPureness = getPureness(color);
            
            { // Apply hue to source color 
                float3 colorHSV = RGBtoHSV(color);
                float colorS = colorHSV.y;
                float3 giHSV = RGBtoHSV(gi);
                colorHSV.x = giHSV.x;
                colorHSV.y = giHSV.y;
                float coef = saturate(
                    5.0 // base
                    *saturate(
                        fGIHueBiais // user setting
                        +0.5*(1.0-safePow(colorBrightness,0.5)) // color brightness bonus
                    ) //
                    *(1.0-colorBrightness*0.8) // color brightness
                    *(1.0-colorS*0.5) // color saturation
                    *giBrightness // gi brightness
                    *giHSV.y // gi saturation
                );
                    
                color = lerp(color,HSVtoRGB(colorHSV),coef);
            }
            
            // Base color
            float3 result = color;
            
            // GI
            
            // Dark areas
            float darkMerging = fGIDarkMerging;
            if(bGIHDR) {
                float avg = getBrightness(getColorSamplerLod(giSmoothPassSampler,float2(0.5,0.5),9.0).rgb);
                darkMerging *= 1.0-avg/2.0;
            }
            float darkBrightnessLevel = saturate(originalColorBrightness);
            float darkB = safePow(1.0-darkBrightnessLevel,3.0);
            // 0.13.1 merging
            //result += (lerp(darkBrightnessLevel,result,saturate(colorPureness-giPureness)*5)+0.1)*gi*darkB*darkMerging*4.0;
            // 0.12.0 merging
            result += lerp(0,(result+0.1)*gi,darkB*darkMerging*4.0);
            
            
            // Light areas
            float brightB = colorBrightness*safePow(colorBrightness,0.5)*safePow(1.0-colorBrightness,0.75);
            result += lerp(0,gi,brightB*fGILightMerging);
            
            // Mixing
            result = lerp(color,result,fGIFinalMerging);
            
            // Apply AO after GI
            {
                float ao = passColor.a;
                ao = computeAo(ao,getBrightness(result.rgb),giBrightness);
                result *= ao;
            }
            outResult = float4(saturate(result),1);
            
            
        }
    }
    

    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
    {        
        float3 result = 0;
        
        if(iDebug==DEBUG_OFF) {
            result = getColorSampler(resultSampler,coords).rgb;
            float depth = ReShade::GetLinearizedDepth(coords);
            float3 color = getColor(coords).rgb;
                
            // SSR
            if(bSSR && fMergingSSR>0.0) {
                float colorBrightness = getBrightness(result);
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
            
            result = saturate(result);
            
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
            
            //if(bTest4) ao = getColorSampler(giPassSampler,coords).a;
            result = ao;
            
        } else if(iDebug==DEBUG_SSR) {
            float3 color = getColor(coords).rgb;       

            result = computeSSR(coords,getBrightness(color))*2;
            //result = getColorSampler(ssrAccuSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_ROUGHNESS) {
#if ROUGHNESS
            result = getRoughness(coords);
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
            
        } else if(iDebug==DEBUG_AMBIENT) {
#if AMBIENT_ON
            result = getRemovedAmbiantColor();
#else   
            result = 0;
#endif    
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT<
        ui_label = "DH_UBER_RT 0.15.0";
        ui_tooltip = 
            "_____________ DH_UBER_RT _____________\n"
            "\n"
            " ver 0.15.0 (2023-08-30)  by AlucardDH\n"
#if DX9_MODE
            "         DX9 limited edition\n"
#endif
            "\n"
            "______________________________________";
    > {
#if AMBIENT_ON
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SavePreviousAmbientPass;
            RenderTarget = previousAmbientTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_AmbientPass;
            RenderTarget = ambientTex;
            
            ClearRenderTargets = false;
                        
            BlendEnable = true;
            BlendOp = ADD;
            SrcBlend = SRCALPHA;
            SrcBlendAlpha = ONE;
            DestBlend = INVSRCALPHA;
            DestBlendAlpha = ONE;
        }
#endif
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
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RayColorPass;
            RenderTarget = rayColorTex;
        }
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