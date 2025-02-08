////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT 0.20.1 (2025-02-08)
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

#ifndef USE_MARTY_LAUNCHPAD_MOTION
 #define USE_MARTY_LAUNCHPAD_MOTION 0
#endif
#ifndef USE_VORT_MOTION
 #define USE_VORT_MOTION 0
#endif


#define HUD_SIZE 256


#define SPHERE 0

#if SPHERE
    #ifndef SPHERE_RATIO
     #define SPHERE_RATIO 8
    #endif
#endif


// HIDDEN PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////
// Should not be modified but can help if you really want to squeeze some FPS at the cost of lower fidelity

#define DX9_MODE (__RENDERER__==0x9000)

// Enable ambient light functionality
#define TEX_NOISE DX9_MODE
#define RESV_SCALE 1

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
#define DEBUG_THICKNESS 10

#define RT_HIT_DEBUG_LIGHT 2.0
#define RT_HIT 1.0
#define RT_HIT_BEHIND 0.5
#define RT_HIT_GUESS 0.25
#define RT_HIT_SKY -0.5
#define RT_MISSED -1.0
#define RT_MISSED_FAST -2.0

#define PI 3.14159265359
#define SQRT2 1.41421356237

// Can be used to fix wrong screen resolution
#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT

#define RENDER_WIDTH INPUT_WIDTH
#define RENDER_HEIGHT INPUT_HEIGHT

#define RENDER_SIZE int2(RENDER_WIDTH,RENDER_HEIGHT)

#define BUFFER_SIZE int2(INPUT_WIDTH,INPUT_HEIGHT)
#define BUFFER_SIZE3 int3(INPUT_WIDTH,INPUT_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE)


// MACROS /////////////////////////////////////////////////////////////////
// Don't touch this
#define getColor(c) saturate(tex2Dlod(ReShade::BackBuffer,float4((c).xy,0,0))*(bBaseAlternative?fBaseColor:1))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4((c).xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4((c).xy,0,0))
#define maxOf3(a) max(max(a.x,a.y),a.z)
#define minOf3(a) min(min(a.x,a.y),a.z)
#define avgOf3(a) (((a).x+(a).y+(a).z)/3.0)
#define CENTER float2(0.5,0.5)
#define S_PR MagFilter=POINT;MinFilter=POINT;MipFilter= POINT;AddressU=REPEAT;AddressV=REPEAT;AddressW=REPEAT;
#define S_PC MagFilter=POINT;MinFilter=POINT;MipFilter= POINT;AddressU=Clamp;AddressV=Clamp;AddressW=Clamp;

//////////////////////////////////////////////////////////////////////////////

#if USE_MARTY_LAUNCHPAD_MOTION
namespace Deferred {
    texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sMotionVectorsTex { Texture = MotionVectorsTex;  };
}
#elif USE_VORT_MOTION
    texture2D MotVectTexVort {  Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; S_PC  };
#else
    texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sTexMotionVectorsSampler { Texture = texMotionVectors; S_PC };
#endif


namespace DH_UBER_RT_0201 {

// Textures

#if TEX_NOISE
    texture blueNoiseTex < source ="dh_rt_noise.png" ; > { Width = 512; Height = 512; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex; S_PR};
#endif

#if !DX9_MODE
    texture ambientTex { Width = 1; Height = 1; Format = RGBA16F; };
    sampler ambientSampler { Texture = ambientTex; };   

    texture previousAmbientTex { Width = 1; Height = 1; Format = RGBA16F; };
    sampler previousAmbientSampler { Texture = previousAmbientTex; }; 
    
    texture previousColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler previousColorSampler { Texture = previousColorTex; };
    
    texture previousDepthTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; MipLevels = 6;  };
    sampler previousDepthSampler { Texture = previousDepthTex; MinLOD = 0.0f; MaxLOD = 5.0f; };
#endif

    texture depthTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; MipLevels = 6;  };
    sampler depthSampler { Texture = depthTex; MinLOD = 0.0f; MaxLOD = 5.0f; };

    // Roughness Thickness
    texture previousRTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler previousRTFSampler { Texture = previousRTFTex; };
    texture RTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler RTFSampler { Texture = RTFTex; S_PR};
 
    texture bestRayTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler bestRaySampler { Texture = bestRayTex; S_PC };
    
    texture bestRayFillTex { Width = RENDER_WIDTH/RESV_SCALE; Height = RENDER_HEIGHT/RESV_SCALE; Format = RGBA16F; };
    sampler bestRayFillSampler { Texture = bestRayFillTex; S_PC};
    texture previousBestRayTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler previousBestRaySampler { Texture = previousBestRayTex; S_PC};
   
#if SHPERE
    texture previousSphereTex { Width = RENDER_WIDTH/SPHERE_RATIO; Height = RENDER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler previousSphereSampler { Texture = previousSphereTex;};
    
    texture sphereTex { Width = RENDER_WIDTH/SPHERE_RATIO; Height = RENDER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler sphereSampler { Texture = sphereTex;};
#endif

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA16F; };
    sampler normalSampler { Texture = normalTex; S_PC};
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
    texture rayColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler rayColorSampler { Texture = rayColorTex; };
    
    texture giPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler giPassSampler { Texture = giPassTex; S_PR};

    texture giPass2Tex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler giPass2Sampler { Texture = giPass2Tex; MinLOD = 0.0f; MaxLOD = 5.0f; S_PR};

    texture giSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f; };
    
    texture giSmooth2PassTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8;  };
    sampler giSmooth2PassSampler { Texture = giSmooth2PassTex; };
    
    texture giAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8;};
    sampler giAccuSampler { Texture = giAccuTex;};
    
    texture giPreviousAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler giPreviousAccuSampler { Texture = giPreviousAccuTex;};//S_PR

    texture reinhardTex { Width = 1; Height = 1; Format = RGBA16F; };
    sampler reinhardSampler { Texture = reinhardTex; };   
   
    // SSR texture
    texture ssrPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler ssrPassSampler { Texture = ssrPassTex;};//S_PR
          
    texture ssrAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8;  MipLevels = 6; };
    sampler ssrAccuSampler { Texture = ssrAccuTex; MinLOD = 0.0f; MaxLOD = 5.0f; };
    
    texture ssrPreviousAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler ssrPreviousAccuSampler { Texture = ssrPreviousAccuTex;};
    
    
   
    
// Structs
    struct RTOUT {
        float3 wp;
        float status;
    };
    

// Internal Uniforms
    uniform int framecount < source = "framecount"; >;
    uniform int random < source = "random"; min = 0; max = 512; >;

// Parameters

/*
    uniform float fTest <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.01;
    uniform float fTest2 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 25.0;
        ui_step = 0.001;
    > = 8;
    uniform float fTest3 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.25;
    uniform float fTest4 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.6;
    uniform int iTest <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0; ui_max = 4;
        ui_step = 1;
    > = 2;
    uniform int iTest2 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0; ui_max = 64;
        ui_step = 1;
    > = 12;
    uniform bool bTest <ui_category="Test";> = true;
    uniform bool bTest2 <ui_category="Test";> = true;
    uniform bool bTest3 <ui_category="Test";> = false;
    uniform bool bTest4 <ui_category="Test";> = false;
    uniform bool bTest5 <ui_category="Test";> = false;
    uniform bool bTest6 <ui_category="Test";> = false;
    uniform bool bTest7 <ui_category="Test";> = false;
    uniform bool bTest8 <ui_category="Test";> = false;
    uniform bool bTest9 <ui_category="Test";> = false;
    uniform bool bTest10 <ui_category="Test";> = false;
    uniform bool bTest11 <ui_category="Test";> = false;
    uniform bool bTest12 <ui_category="Test";> = false;
*/
 
// DEBUG 

    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0GI\0AO\0SSR\0Roughness\0Depth\0Normal\0Sky\0Motion\0Ambient light\0Thickness\0";
        ui_tooltip = "Debug the different components of the shader";
    > = 0;
    uniform int iDebugPass <
        ui_category= "Debug";
        ui_type = "combo";
        ui_label = "GI/AO/SSR pass";
        ui_items = "New rays\0Resample\0Spatial denoising\0Temporal denoising\0Merging\0";
        ui_tooltip = "GI/AO/SSR only: Debug the intermediate steps of the shader";
    > = 3;
    
// DEPTH

    uniform bool bSkyAt0 <
        ui_category = "Game specific hacks";
        ui_label = "Sky at Depth=0 (SWTOR)";
    > = false;
    
    uniform bool bDepthMulti5 <
        ui_category = "Game specific hacks";
        ui_label = "Depth multiplier=5 (Skyrim SE, Other DX9>11 games)";
    > = false;
    

    uniform float fSkyDepth <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "Sky Depth";
        ui_min = 0.00; ui_max = 1.00;
        ui_step = 0.001;
        ui_tooltip = "Define where the sky starts to prevent if to be affected by the shader";
    > = 0.999;
    
    uniform float fWeaponDepth <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "Weapon Depth";
        ui_min = 0.00; ui_max = 1.00;
        ui_step = 0.001;
        ui_tooltip = "Define where the weapon ends to prevent it to affect the SSR";
    > = 0.001;

    uniform float fNormalRoughness <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "Normal roughness";
        ui_min = 0.000; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.1;
    

    uniform int iRoughnessRadius <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "Roughness Radius";
        ui_min = 1; ui_max = 4;
        ui_step = 2;
        ui_tooltip = "Define the max distance of roughness computation.\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 2;
    
    uniform bool bSmoothNormals <
        ui_category = "Common";
        ui_label = "Smooth Normals";
    > = false;



// AMBIENT LIGHT 
    uniform bool bRemoveAmbient <
        ui_category = "Ambient light";
        ui_label = "Remove Source Ambient light";
    > = true;
    
    uniform float fSourceAmbientIntensity <
        ui_type = "slider";
        ui_category = "Ambient light";
        ui_label = "Strength";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.75;

    uniform float fRemoveAmbientAutoAntiFlicker <
        ui_type = "slider";
        ui_category = "Remove ambient light";
        ui_label = "Compromise flicker/reactvity";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.5;
    
// GI

	uniform float fGIRenderScale <
        ui_category="GI/AO: 1st Pass (New rays)";
        ui_label = "GI Render scale";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.333;
    
    uniform int iRTMaxRays <
        ui_type = "slider";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "Max rays...";
        ui_min = 1; ui_max = 6;
        ui_step = 1;
        ui_tooltip = "Maximum number of rays from 1 pixel if the first miss\n"
                    "Lower=Darker image, better performance\n"
                    "Higher=Less noise, brighter image\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 2;
    
    uniform int iRTMaxRaysMode <
        ui_type = "combo";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "... per pixel of";
        ui_items = "Render size\0Target size\0";
#if DX9_MODE
    > = 1;
#else
    > = 0;
#endif

    uniform float fGIAvoidThin <
        ui_type = "slider";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "Avoid thin objects: max thickness";
        ui_tooltip = "Reduce detection of grass or fences";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.50;

    uniform int iHudBorderProtectionRadius <
        ui_type = "slider";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "Avoid HUD: Radius";
        ui_tooltip = "Reduce chances of detecting large lights from the HUD. Disable if you're using REST or if HUD is hidden";
        ui_min = 1; ui_max = 256;
        ui_step = 1;
    > = 180;
    
    uniform float fHudBorderProtectionStrength <
        ui_type = "slider";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "Avoid HUD: Strength";
        ui_tooltip = "Reduce chances of detecting large lights from the HUD. Disable if you're using REST or if HUD is hidden";
        ui_min = 0.0; ui_max = 8.0;
        ui_step = 0.01;
    > = 4.0;
        
#if !DX9_MODE    
    uniform int iMemRadius <
        ui_type = "slider";
        ui_category = "GI/AO: 2nd Pass (Resample)";
        ui_label = "Memory radius";
        ui_min = 0; ui_max = 3;
        ui_step = 1;
    > = 2;
#else
    #define iMemRadius 1
#endif

    // Denoising

    uniform int iSmoothSamples <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "Spatial: Samples";
        ui_min = 1; ui_max = 64;
        ui_step = 1;
        ui_tooltip = "Define the number of denoising samples.\n"
                    "Higher:less noise, less performances\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";    
#if DX9_MODE
    > = 16;
#else
    > = 10;
#endif
    
    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "Spatial: Radius";
        ui_min = 0; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the max distance of smoothing.\n";
    > = 16;
    
    uniform int iGIFrameAccu <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "GI Temporal accumulation";
        ui_min = 1; ui_max = 32;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
#if DX9_MODE
    > = 32;
#else
    > = 8;
#endif
    
    uniform int iAOFrameAccu <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "AO Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 10;
    
    uniform float fGIRayColorMinBrightness <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "GI Ray min brightness";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.0;
    
    uniform int iGIRayColorMode <
        ui_type = "combo";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "GI Ray brightness mode";
        ui_items = "Crop\0Smoothstep\0Linear\0Gamma\0";
#if DX9_MODE
    > = 0;
#else
    > = 1;
#endif    

    uniform float fGIDistanceAttenuation <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Distance attenuation";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.350;
    
    
    uniform float fSkyColor <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Sky color";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the sky can brighten the scene";
    > = 0.5;
    
    uniform float fSaturationBoost <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Saturation boost";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.1;
    
    uniform float fGIDarkAmplify <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Dark color compensation";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Brighten dark colors, useful in dark corners";
    > = 0.10;
    
    uniform float fGIBounce <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Bounce intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define if GI bounces in following frames";
    > = 0.5;

    uniform float fGIHueBiais <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Hue Biais";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much base color can take GI hue.";
    > = 0.5;
    
    uniform float fGILightMerging <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "In Light intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much bright areas are affected by GI.";
    > = 0.10;
    uniform float fGIDarkMerging <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "In Dark intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much dark areas are affected by GI.";
    > = 0.5;
    
    uniform float fGIFinalMerging <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "General intensity";
        ui_min = 0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the whole image is affected by GI.";
    > = 1.0;
    
    uniform float fGIOverbrightToWhite <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Overbright to white";
        ui_min = 0.0; ui_max = 5.0;
        ui_step = 0.001;
    > = 0.2;
    
    uniform bool bRreinhardFinalMerging <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Reinhard Tonemap";
        ui_tooltip = "Improve details in dark and bright areas.";
    > = true;
    
    uniform float fRreinhardStrength <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Reinhard Tonemap strength";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Improve details in dark and bright areas.";
    > = 0.5;
    
// AO

    uniform float fAOBoostFromGI <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Boost from GI";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.5;
    
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
        ui_tooltip = "Define the intensity of AO";
    > = 0.9;
    
    uniform int iAODistance <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Distance";
        ui_min = 0; ui_max = BUFFER_WIDTH;
        ui_step = 1;
    > = BUFFER_WIDTH/6;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Pow";
        ui_min = 0.001; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 1.0;
    
    uniform float fAOLightProtect <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Light protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of bright areas to avoid washed out highlights";
    > = 0.6;  
    
    uniform float fAODarkProtect <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Dark protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of dark areas to avoid totally black and unplayable parts";
    > = 0.15;

    uniform float fAoProtectGi <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "GI protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.05;
    


// SSR
    uniform bool bSSR <
        ui_category = "SSR";
        ui_label = "Enable SSR";
        ui_tooltip = "Toggle SSR";
    > = false;
    
	uniform float fSSRRenderScale <
        ui_category="SSR";
        ui_label = "SSR Render scale";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.5;
    
    uniform int iSSRFrameAccu <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "SSR Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
#if DX9_MODE
    > = 12;
#else
    > = 10;
#endif
    
    uniform bool bSSRHQSubPixel <
        ui_category = "SSR";
        ui_label = "High precision sub-pixels";
    > = false;
    
    uniform bool bSSRRinR <
        ui_category = "SSR";
        ui_label = "Reflections in reflection";
    > = false;
    
    uniform int iSSRCorrectionMode <
        ui_type = "combo";
        ui_category = "SSR";
        ui_label = "Geometry correction mode";
        ui_items = "No correction\0FOV\0";
        ui_tooltip = "Try modifying this value is the relfection seems wrong";
    > = 1;
    
    uniform float fSSRCorrectionStrength <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Geometry correction strength";
        ui_min = -1; ui_max = 1;
        ui_step = 0.001;
        ui_tooltip = "Try modifying this value is the relfection seems wrong";
    > = 0;
    
    uniform float fSSRMergingRoughness <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Roughness reflexivity";
        ui_min = 0.000; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define how much the roughness decrease reflection intensity";
    > = 0.5;
    
    uniform float fSSRMergingOrientation <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Orientation reflexivity";
        ui_min = 0.000; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Higher value make the wall less reflective than the floor";
    > = 0.5;

    uniform float fSSRMerging <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "SSR Intensity";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define this intensity of the Screan Space Reflection.";
    > = 0.5;
    
// Merging
        
    uniform float fDistanceFading <
        ui_type = "slider";
        ui_category = "Fianl Merging";
        ui_label = "Distance fading";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Distance from where the effect is less applied.";
    > = 0.9;
    
    
    uniform float fBaseColor <
        ui_type = "slider";
        ui_category = "Fianl Merging";
        ui_label = "Base color";
        ui_min = 0.0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Simple multiplier for the base image.";
    > = 1.0;
    
    uniform bool bBaseAlternative <
        ui_category = "Fianl Merging";
        ui_label = "Base color alternative method";
    > = false;

    uniform int iBlackLevel <
        ui_type = "slider";
        ui_category = "Fianl Merging";
        ui_label = "Black level ";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 0;
    
    uniform int iWhiteLevel <
        ui_type = "slider";
        ui_category = "Fianl Merging";
        ui_label = "White level";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 255;
    
// Debug light
    uniform bool bDebugLight <
        ui_type = "color";
        ui_category = "Debug Light";
        ui_label = "Enable";
    > = false;
    
    uniform bool bDebugLightOnly <
        ui_type = "color";
        ui_category = "Debug Light";
        ui_label = "No scene light";
    > = true;
    
    uniform float3 fDebugLightColor <
        ui_type = "color";
        ui_category = "Debug Light";
        ui_label = "Color";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = float3(1.0,0,0);
    
    uniform float3 fDebugLightPosition <
        ui_type = "slider";
        ui_category = "Debug Light";
        ui_label = "XYZ Position";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = float3(0.5,0.5,0.05);
    
    uniform int iDebugLightSize <
        ui_type = "slider";
        ui_category = "Debug Light";
        ui_label = "Source Size";
        ui_min = 1; ui_max = 100;
        ui_step = 1;
    > = 2;
    
    uniform bool bDebugLightZAtDepth <
        ui_type = "color";
        ui_category = "Debug Light";
        ui_label = "Z at screen depth";
    > = true;


    
// FUCNTIONS

	bool isScaledProcessed(float2 coords) {
		return coords.x>=0 && coords.y>0 && coords.x<=fGIRenderScale && coords.y<=fGIRenderScale;
	}

    float safePow(float value, float power) {
        return pow(abs(value),power);
    }
    
    float3 safePow(float3 value, float power) {
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
    
    float hueDistance(float a,float b) {
        return min(abs(a-b),1.0-abs(a-b));
    }
    
    float getPureness(float3 rgb) {
        return maxOf3(rgb)-minOf3(rgb);
    }
    
    float getBrightness(float3 rgb) {
        return maxOf3(rgb);
    }

    float3 RGBtoOKL(float3 rgb) {

        // Step 1: Linearize RGB
        float3 linearRGB = rgb <= 0.04045 ? rgb / 12.92 : pow((rgb + 0.055) / 1.055, 2.4);

        // Step 2: Linear RGB to LMS
        float3 lms = mul(float3x3(
            0.4122214708, 0.5363325363, 0.0514459929,
            0.2119034982, 0.6806995451, 0.1073969566,
            0.0883024619, 0.2817188376, 0.6299787005
        ), linearRGB);

        // Step 3: Non-linear transformation (cube root)
        float3 lms_nl = pow(lms, 1.0 / 3.0);

        // Step 4: LMS to OKLab
        float3 oklab = mul(float3x3(
            0.2104542553, 0.7936177850, -0.0040720468,
            1.9779984951, -2.4285922050, 0.4505937099,
            0.0259040371, 0.7827717662, -0.8086757660
        ), lms_nl);

        return oklab;
    }

    float3 OKLtoRGB(float3 oklab) {
        // Step 1: OKLab to LMS
        float3 lms_nl = mul(float3x3(
            1.0, 0.3963377774, 0.2158037573,
            1.0, -0.1055613458, -0.0638541728,
            1.0, -0.0894841775, -1.2914855480
        ), oklab);

        // Step 2: Reverse Non-linear transformation (cube)
        float3 lms = lms_nl * lms_nl * lms_nl;

        // Step 3: LMS to linear RGB
        float3 linearRGB = mul(float3x3(
            4.0767416621, -3.3077115913, 0.2309699292,
            -1.2684380046, 2.6097574011, -0.3413193965,
            -0.0041960863, -0.7034186147, 1.7076147010
        ), lms);

        // Step 4: De-linearize RGB
        float3 rgb = linearRGB <= 0.0031308 ? linearRGB * 12.92 : 1.055 * pow(linearRGB, 1.0 / 2.4) - 0.055;

        return rgb;
    }


// Screen

    float getDepthMultiplier() {
        return bDepthMulti5 ? 5 : 1;
    }

    float getSkyDepth() {
        return fSkyDepth*getDepthMultiplier();
    }

    float isSky(float depth) {
        return bSkyAt0 ? depth==0 : depth>getSkyDepth();
    }

    float3 getNormal(float2 coords) {
        float3 normal = -(tex2Dlod(normalSampler,float4(coords,0,0)).xyz-0.5)*2;
        return normalize(normal);
    }

    float getDepth(float2 coords) {
        float d = ReShade::GetLinearizedDepth(coords);
        if(d<fWeaponDepth) d *= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fSkyDepth;
        return d*getDepthMultiplier();
    }
    
    
    float4 getRTF(float2 coords) {
        return getColorSampler(RTFSampler,coords);
    }
    
    float4 getDRTF(float2 coords) {
        
        float4 drtf = getDepth(coords);
        drtf.yzw = getRTF(coords).xyz;
        if(fNormalRoughness>0 && !isSky(drtf.x)) {
            float roughness = drtf.y;
            drtf.x += drtf.x*roughness*fNormalRoughness*0.05/(fGIRenderScale*getDepthMultiplier());
        }
        drtf.z = (0.01+drtf.z)*drtf.x*320;
        drtf.z *= (0.25+drtf.x);
        
        return drtf;
    }
    
    bool inScreen(float3 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0
            && coords.z>=0.0 && coords.z<=getDepthMultiplier();
    }
    
    bool inScreen(float2 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0;
    }
    
    float3 fovCorrectedBufferSize() {
        float3 result = BUFFER_SIZE3;
        if(iSSRCorrectionMode==1) result.xy *= 1.0+fSSRCorrectionStrength;
        return result;
    }
    
    float3 getWorldPositionForNormal(float2 coords,bool ignoreRoughness) {
        float depth = getDepth(coords);
        if(!ignoreRoughness && fNormalRoughness>0 && !isSky(depth)) {
            float roughness = getRTF(coords).x;
            if(bSmoothNormals) roughness *= 1.5;
            depth /= getDepthMultiplier();
            depth += depth*roughness*fNormalRoughness*0.05;
            depth *= getDepthMultiplier();
        }
        
        float3 result = float3((coords-0.5)*depth,depth);
        result *= fovCorrectedBufferSize();
        return result;
    }
    
    float3 getWorldPosition(float2 coords,float depth) {
        float3 result = float3((coords-0.5)*depth,depth);

        result *= fovCorrectedBufferSize();
        return result;
    }

    float3 getScreenPosition(float3 wp) {
        float3 result = wp/fovCorrectedBufferSize();
        result.xy /= result.z;
        return float3(result.xy+0.5,result.z);
    }
    




// Vector operations
    int getPixelIndex(float2 coords,int2 size) {
        int2 pxCoords = coords*size;
        return pxCoords.x+pxCoords.y*size.x+random;
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
        v = abs((getColorSampler(blueNoiseSampler,noiseCoords).rg-0.5)*2.0);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);

        v.x = randomValue(seed);
        v.y = randomValue(seed);
#endif
        return v;
    }
    
#if TEX_NOISE
#else
    float3 randomTriple(float2 coords,in out uint seed) {
        float3 v = 0;
        v.x = randomValue(seed);
        v.y = randomValue(seed);
        v.z = randomValue(seed);
        return v;
    }
#endif

    float3 randomTriple(float2 coords) {
        float3 v = 0;
#if TEX_NOISE
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        v = getColorSampler(blueNoiseSampler,noiseCoords).rgb;
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE)+random+framecount;
        v = randomTriple(coords,seed);
#endif
        return v;
    }
    
    float4 getRayColor(float2 coords) {
        return getColorSampler(rayColorSampler,coords);
    }
    
    bool isEmpty(float3 v) {
        return maxOf3(v)==0;
    }

// PS
    
    float2 getPreviousCoords(float2 coords) {
#if USE_MARTY_LAUNCHPAD_MOTION
        float2 mv = getColorSampler(Deferred::sMotionVectorsTex,coords).xy;
        return coords+mv;
#elif USE_VORT_MOTION
        float2 mv = getColorSampler(sMotVectTexVort,coords).xy;
        return coords+mv;
#else
        float2 mv = getColorSampler(sTexMotionVectorsSampler,coords).xy;
        return coords+mv;
#endif
    } 

    float roughnessPass(float2 coords,float refDepth) {
     
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
        
        roughness *= 0.5+refDepth*2;
        
        return roughness;
    }

    float thicknessPass(float2 coords, float refDepth,out float sky) {
    
        if(isSky(refDepth)) {
            sky = 0;
            return 1000;
        }

        int iThicknessRadius = 4;
        
        float2 thickness = 0;
        float previousXdepth = refDepth;
        float previousYdepth = refDepth;
        float depthLimit = refDepth*0.015;
        float depth;
        float2 currentCoords;
        
        float2 orientation = normalize(randomCouple(coords*PI)-0.5);
        
        bool validPos = true;
        bool validNeg = true;
        sky = 1.0;
        
        [loop]
        for(int d=1;d<=iThicknessRadius;d++) {
            float2 step = orientation*ReShade::PixelSize*d;
            
            if(validPos) {
                currentCoords = coords+step;
                depth = getDepth(currentCoords);
                if(isSky(depth)) {
                    sky = min(sky,float(d)/iThicknessRadius);
                }
                if(depth-previousXdepth<=depthLimit) {
                    thickness.x = d;
                    previousXdepth = depth;
                } else {
                    validPos = false;
                }
            }
        
            if(validNeg) {
                currentCoords = coords-step;
                depth = getDepth(currentCoords);
                if(isSky(depth)) {
                    sky = min(sky,float(d)/iThicknessRadius);
                } 
                if(depth-previousYdepth<=depthLimit) {
                    thickness.y = d;
                    previousYdepth = depth;
                } else {
                    validNeg = false;
                }
            }
        }        
        
        thickness /= iThicknessRadius;
        
        
        return (thickness.x+thickness.y)*0.5;
    }
    
    float distanceHue(float refHue, float hue) {
        if(refHue<hue) {
            return min(hue-refHue,refHue+1.0-hue);
        } else {
            return min(refHue-hue,hue+1.0-refHue);
        }
    }
    
    float scoreLight(float3 rgb,float3 hsv) {
        return hsv.y * hsv.z;
    }
    
    void PS_RTFS_save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRTFS : SV_Target0) {
        outRTFS = getColorSampler(RTFSampler,coords);
    }    
    
    void PS_RTFS(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRTFS : SV_Target0) {
        float depth = getDepth(coords);
        
        float2 previousCoords = getPreviousCoords(coords);
        
        float4 RTFS;
        RTFS.x = roughnessPass(coords,depth);
        RTFS.y = thicknessPass(coords,depth,RTFS.a);
        
        float4 previousRTFS = getColorSampler(previousRTFSampler,previousCoords);
        RTFS.y = lerp(previousRTFS.y,RTFS.y,0.33);
        RTFS.a = min(RTFS.a,0.1+previousRTFS.a);

        
        RTFS.z = 1;
        
        outRTFS = RTFS;
    }

#if!DX9_MODE    
    void PS_SavePreviousAmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {
        outAmbient = getColorSampler(ambientSampler,CENTER);
    }
    
    
    
    void PS_AmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {

        float4 previous = getColorSampler(previousAmbientSampler,CENTER);
        bool first = false;
        if(previous.a<=2.0/255.0) {
			previous = 1;
			first = true;
        }
        //previous.rgb += 1.0/255.0;
        float b = maxOf3(previous.rgb);
        
        
        float3 result = 1.0;
        float bestB = maxOf3(previous.rgb);
        
        float2 currentCoords = 0;
        float2 bestCoords = CENTER;
        float2 rand = randomCouple(coords);
        
        float2 size = BUFFER_SIZE;
        float stepSize = BUFFER_WIDTH/16.0;
        float2 numSteps = size/(stepSize+1);
        
        float avgBrightness = 0;
        int count = 0;
            
        //float2 rand = randomCouple(currentCoords);
        for(int it=0;it<=4 && stepSize>=1;it++) {
            float2 stepDim = stepSize/BUFFER_SIZE;
        
            for(currentCoords.x=bestCoords.x-stepDim.x*(numSteps.x/2);currentCoords.x<=bestCoords.x+stepDim.x*(numSteps.x/2);currentCoords.x+=stepDim.x) {
                for(currentCoords.y=bestCoords.y-stepDim.y*(numSteps.y/2);currentCoords.y<=bestCoords.y+stepDim.y*(numSteps.y/2);currentCoords.y+=stepDim.y) {
                   float2 c = currentCoords+rand*stepDim;
                    float3 color = getColor(c).rgb;
                    b = maxOf3(color);
                    avgBrightness += b;
                    if(b>0.1 && b<bestB) {
                    
                        bestCoords = c;
                        result = min(result,color);
                        bestB = b;
                    }
                    count += 1;
                }
            }
            size = stepSize;
            numSteps = 8;
            stepSize = size.x/numSteps.x;
        }
        
        result = first ? result : min(previous.rgb,result);
        avgBrightness /= count;
        outAmbient = lerp(previous,float4(result,avgBrightness),max(fRemoveAmbientAutoAntiFlicker,0.1)*3.0/60.0);
    }
    
    float3 getRemovedAmbiantColor() {
        if(bRemoveAmbient) {
            float3 color = getColorSampler(ambientSampler,CENTER).rgb;
            color += color.x;
            return color;
        } else {
            return 0;
        }
    }
    
    float getAverageBrightness() {
        return getColorSampler(ambientSampler,CENTER).a;
    }
    
    float3 filterAmbiantLight(float3 sourceColor) {
        float3 color = sourceColor;
        if(bRemoveAmbient) {
			float3 colorHSV = RGBtoHSV(color);
	        float3 removed = getRemovedAmbiantColor();
	        float3 removedHSV = RGBtoHSV(removed);
	        float3 removedTint = removed - minOf3(removed); 
	        float3 sourceTint = color - minOf3(color);
	        
	        float hueDist = maxOf3(abs(removedTint-sourceTint));
	        
	        float removal = saturate(1.0-hueDist*saturate(colorHSV.y+colorHSV.z));
	        color -= removed*(1.0-hueDist)*fSourceAmbientIntensity*0.333*(1.0-colorHSV.z);
	        color = saturate(color);
        }
        return color;
    }
    
#else
    float3 getRemovedAmbiantColor() {
        if(bRemoveAmbient) {
            return 2.0/255.0;
        } else {
            return 0;
        }
    }

    float3 filterAmbiantLight(float3 sourceColor) {
        return bRemoveAmbient ? sourceColor - 2.0/255.0 : sourceColor;
    }
    
    float getAverageBrightness() {
        return 0.5;
    }    
#endif

    float4 mulByA(float4 v) {
        v.rgb *= v.a;
        return v;
    }


    float4 computeNormal(float3 wpCenter,float3 wpNorth,float3 wpEast) {
        return float4(normalize(cross(wpCenter - wpNorth, wpCenter - wpEast)),1.0);
    }
    
    float4 computeNormal(float2 coords,float3 offset,bool ignoreRoughness) {
        float3 posCenter = getWorldPositionForNormal(coords,ignoreRoughness);
        float3 posNorth  = getWorldPositionForNormal(coords - offset.zy,ignoreRoughness);
        float3 posEast   = getWorldPositionForNormal(coords + offset.xz,ignoreRoughness);
        
        return computeNormal(posCenter,posNorth,posEast);
    }


    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0, out float4 outDepth : SV_Target1) {
        
        float3 offset = float3(ReShade::PixelSize, 0.0);
        
        float4 normal = computeNormal(coords,offset,false);
        
        if(bSmoothNormals) {
            float3 offset2 = offset * 7.5*(1.0-getDepth(coords));
            float4 normalTop = computeNormal(coords-offset2.zy,offset,true);
            float4 normalBottom = computeNormal(coords+offset2.zy,offset,true);
            float4 normalLeft = computeNormal(coords-offset2.xz,offset,true);
            float4 normalRight = computeNormal(coords+offset2.xz,offset,true);
            
            normalTop.a *= smoothstep(1,0,distance(normal.xyz,normalTop.xyz)*1.5)*2;
            normalBottom.a *= smoothstep(1,0,distance(normal.xyz,normalBottom.xyz)*1.5)*2;
            normalLeft.a *= smoothstep(1,0,distance(normal.xyz,normalLeft.xyz)*1.5)*2;
            normalRight.a *= smoothstep(1,0,distance(normal.xyz,normalRight.xyz)*1.5)*2;
            
            float4 normal2 = 
                mulByA(normal)
                +mulByA(normalTop)
                +mulByA(normalBottom)
                +mulByA(normalLeft)
                +mulByA(normalRight)
            ;
            if(normal2.a>0) {
                normal2.xyz /= normal2.a;
                normal.xyz = normalize(normal2.xyz);
            }
            
        }
        
        outNormal = float4(normal.xyz/2.0+0.5,1.0);
        outDepth = getDepth(coords);
        
    }
    
    float3 rampColor(float3 color) {	
    	float3 okl = RGBtoOKL(color);
        float b = okl.x;
        float originalB = b;
        
        if(iGIRayColorMode==1) { // smoothstep
            b *= smoothstep(fGIRayColorMinBrightness,1.0,b);
        } else if(iGIRayColorMode==2) { // linear
            b *= saturate(b-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness);
        } else if(iGIRayColorMode==3) { // gamma
            b *= safePow(saturate(b-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness),2.2);
        }
        
        okl.x = originalB>0 ? okl.x * b / originalB : 0;
        return OKLtoRGB(okl);
    }
    
    void PS_RayColorPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {

		
		
        float hueLimit = 0.1;
    
        float2 previousCoords = getPreviousCoords(coords);
    
        float3 refColor = getColor(coords).rgb;
        
        float depth = getDepth(coords);
        if(isSky(depth)) {
            outColor = float4(refColor*fSkyColor,1);
            return;
        }
        
        float3 refHSV = RGBtoHSV(refColor);
        
        int lod = 1;
        float3 tempHSV = refHSV;
        while((1.0-tempHSV.y)*tempHSV.z>0.7 && lod<=5) {
            tempHSV = RGBtoHSV(getColorSamplerLod(resultSampler,previousCoords,lod).rgb);
            
            //refHSV.z = 0.9;
            //refColor = HSVtoRGB(refHSV);
            
            lod ++;
        }
        refHSV.x = tempHSV.x;
        refHSV.yz = max(refHSV.yz,tempHSV.yz);
        refColor = HSVtoRGB(refHSV);
        
        
        if(bRemoveAmbient) {  
            refColor = filterAmbiantLight(refColor);
            refHSV = RGBtoHSV(refColor);
        }
        
        if(fSaturationBoost>0 && refHSV.z*refHSV.y>0.1) {
            refHSV.y = saturate(refHSV.y+fSaturationBoost);
            refColor = HSVtoRGB(refHSV);
        }
        
        if(fGIBounce>0.0) {
            float3 previousColor = getColorSampler(giAccuSampler,previousCoords).rgb;
            float b = getBrightness(refColor);
            refColor = saturate(refColor+previousColor*fGIBounce*(1.0-b)*(0.5+b));
            
        }
        
        float3 result = rampColor(refColor);        
          
        if(fGIDarkAmplify>0) {
            float3 okl = RGBtoOKL(result);
            float avgB = getAverageBrightness();
            okl.x = saturate(okl.x+fGIDarkAmplify*(1.0-avgB)*okl.x*(1.0-okl.x)*10);
            result = OKLtoRGB(okl);
        }
        
        if(getBrightness(result)<fGIRayColorMinBrightness) {
            result = 0; 
        }
        
        outColor = float4(result,1.0);
        
    }
    
    bool isSaturated(float2 coords) {
        return coords.x>=0 && coords.x<=1 && coords.y>=0 && coords.y<=1;
    }
    
#if SHPERE
    int2 sphereSize() {
        return BUFFER_SIZE/SPHERE_RATIO;
    }
    
    
    void PS_Sphere_save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        outColor = getColorSampler(sphereSampler,coords);
    }
    
    void PS_SpherePass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        float2 screencoords = (coords-0.5)*3;
        float2 currentCoords = screencoords+0.5;
        float2 mv = 0;
        
        int count = 0;
        float2 v = normalize(coords - 0.5)/iTest;
        for(int i=1;i<=iTest;i++) {
            float2 c = 0.5+v*i;
            if(!isSaturated(c)) {
                break;
            }
            float2 p = getPreviousCoords(c);
            mv += (p-c);
            count += 1;
        }
        mv /= count;
        
        if(isSaturated(currentCoords)) {
            outColor = getColorSampler(rayColorSampler,currentCoords);
        } else {        
            float2 p = coords + mv;

            if(isSaturated(p)) {
                float3 previousColor= getColorSampler(previousSphereSampler,p).rgb;
                outColor = float4(previousColor,saturate(0.5+getBrightness(previousColor)));
            } else {
                outColor = float4(0,0,0,0);
            }
        }
    }
#endif
 
    int crossing(float deltaZbefore, float deltaZ) {      
        if(deltaZ<=0 && deltaZbefore>0) return -1;
        if(deltaZ>=0 && deltaZbefore<0) return 1;
        return  0;
    }
    
    bool hit(float3 currentWp, float3 screenWp, float depth, float thickness,float3 behindWp) {
        if(fGIAvoidThin>0 && thickness<depth*100*fGIAvoidThin) return false;
        if(currentWp.z>=screenWp.z) {
            if(currentWp.z<=behindWp.z+distance(screenWp,behindWp)*2.0) return true;
            if(currentWp.z<=screenWp.z+2*abs(behindWp.z-screenWp.z)) return true;
            if(currentWp.z<=screenWp.z+thickness*saturate(depth*2)) return true;
        }
        return false;
    }
    
    float3 getDebugLightWp() {
        return getWorldPosition(fDebugLightPosition.xy,bDebugLightZAtDepth ? getDepth(fDebugLightPosition.xy)*0.99 : fDebugLightPosition.z);
    }       

    bool hitLight(float3 refWp, float3 currentWp,float3 targetWp) {
        float sourceDist = distance(refWp,currentWp);
        float targetDist = distance(refWp,targetWp);
        return sourceDist>=targetDist-iDebugLightSize*2;
    }
    
    bool isBehind(float3 refWp,float3 refNormal, float3 hitWp) {
        return distance(refWp-refNormal*0.5,hitWp)>distance(refWp,hitWp);
    }
    
    RTOUT trace(float3 refWp,float3 incrementVector,bool ssr,bool lightTarget,float3 targetWp) {
    
        RTOUT result;
        result.status = RT_MISSED;
        
        float3 currentWp = refWp;
        
        incrementVector = normalize(incrementVector)*0.1;
                
        currentWp += incrementVector;//*(1.0-screenCoords.z);
        float3 screenCoords = getScreenPosition(currentWp);
        float3 screenWp = getWorldPositionForNormal(screenCoords.xy,true);
        
        float4 DRTF = getDRTF(screenCoords.xy);
        
        bool isHit = hit(currentWp, screenWp, DRTF.x,DRTF.z,0);
        
        if(isHit && !ssr && !lightTarget) {
            incrementVector = -incrementVector;
            currentWp += 2*incrementVector;
            screenCoords = getScreenPosition(currentWp);
            screenWp = getWorldPositionForNormal(screenCoords.xy,true);
            DRTF = getDRTF(screenCoords.xy);
            isHit = hit(currentWp, screenWp, DRTF.x,DRTF.z,0);
        }
        
        if(isHit && ssr) {
        	float3 hitNormal = getNormal(screenCoords.xy);
        	incrementVector = reflect(incrementVector,hitNormal);
        	isHit = false;
        }
        
        if(isHit) {
            result.wp = screenWp;
            result.status = RT_MISSED;                 
            return result;
        }
        
        
        float3 refVector = normalize(incrementVector);
        incrementVector = refVector;
                
        float deltaZ = 0.0;
        int stepBehind = 0;
        bool behind = false;
        float3 behindWp = 0;
        float3 beforeBehind = 0;
        float3 behindScreenWp = 0;
        float3 previousScreenWp = refWp;
        float3 previousWp = refWp;
        float3 previousNormal = getNormal(screenCoords.xy);
        
        int step = -1;
        incrementVector *= 0.1;
        
        float maxDist = lightTarget ? distance(currentWp,targetWp) : sqrt(BUFFER_WIDTH*BUFFER_WIDTH+BUFFER_HEIGHT*BUFFER_HEIGHT);
        int maxSteps = ssr?128:16;
        float forcedLength = max(8,maxDist/maxSteps);  
        float2 r = randomCouple(screenCoords.xy);
        float dist = 0;
        while(step<maxSteps && dist<maxDist) {
            step++;
            currentWp += incrementVector;
            screenCoords = getScreenPosition(currentWp);
            
            if(!inScreen(screenCoords)) break;
            
            float3 normal = getNormal(screenCoords.xy);
            bool sameSurface = dot(normal,previousNormal)>0.75;
            
            DRTF = getDRTF(screenCoords.xy);            
            screenWp = getWorldPosition(screenCoords.xy,DRTF.x);
            bool previousBehind = behind;
            behind = currentWp.z>screenWp.z;
            
            if(behind) {
                stepBehind++;
                if(stepBehind==1) {
                    behindWp = screenWp;
                    beforeBehind = previousWp;
                }
            }
            
            if(isSky(DRTF.x)) {
                result.status = RT_HIT_SKY;
                result.wp = currentWp;
            }
            
            if(behind!=previousBehind && sameSurface) {
                float scaledDepth = getColorSamplerLod(depthSampler,screenCoords.xy,1).x;
                if(abs(scaledDepth-DRTF.x)>0.02*DRTF.x) {
                    isHit = false;              
                } else {
                    float previousDiff = abs(previousScreenWp.z-previousWp.z);
                    float diff = abs(screenWp.z-currentWp.z);
                    
                    result.status = behind ? RT_HIT : RT_HIT_BEHIND;
                    result.wp = lerp(previousWp,currentWp,previousDiff/(previousDiff+diff));
                    return result;     
                }   
            }
            
            isHit = hit(currentWp, screenWp, DRTF.x,DRTF.z,behindWp);
            bool isHitBehind = isHit && (stepBehind>1 || (currentWp.z>=screenWp.z+50 && DRTF.z>=50));
            
            if(isHit) {
                float scaledDepth = getColorSamplerLod(depthSampler,screenCoords.xy,1).x;
                if(abs(scaledDepth-DRTF.x)<=0.001*DRTF.x) {
                    result.status = isHitBehind ? RT_HIT_BEHIND : RT_HIT;
                    result.wp = result.status==RT_HIT_BEHIND ? (ssr ? beforeBehind :behindWp) : currentWp;
                    return result;
                }
            }
            
            r = randomCouple(screenCoords.xy);

			if(ssr) {
                deltaZ = screenWp.z-currentWp.z;
                //float l = max(0.5,abs(deltaZ)*0.1);
                float l = deltaZ<-0.5 ? 1 : 0.5*deltaZ/refVector.z;
                incrementVector = refVector*l;
                /*
                deltaZ = screenWp.z-currentWp.z;
                float l = max(0.5,abs(deltaZ)*0.1);
                l += r.y;
                incrementVector = refVector*l;
                */
            } else  {
                float l = 1.00+DRTF.x+r.y;
                incrementVector *= l;
            }
            
            if(!behind) {
                stepBehind = 0;
            }
            
            previousNormal = normal;
            previousWp = currentWp;
            previousScreenWp = screenWp;
            dist = distance(refWp,currentWp);
        }

#if !DX9_MODE  


        if(lightTarget) {
            result.status = RT_HIT;
            result.wp = targetWp;
        }
#endif

        if(ssr && incrementVector.z>0 && inScreen(getScreenPosition(previousWp+incrementVector).xy)) {
            result.status = RT_HIT;
            result.wp = previousWp;
        }
        
        return result;
    }

// GI
    

    
    int getIndexRGB(float3 color, float2 coords,float2 size) {
		float m = maxOf3(color);
		if(m<0.2) {
			return 3;
		} else if(color.r==m && color.g!=m && color.b!=m) {
			return 0;
		} else if(color.g==m && color.r!=m && color.b!=m) {
			return 1;
		} else if(color.b==m && color.r!=m && color.g!=m) {
			return 2;
		} else {
			return 3;
		}
		return 0;
    	
    }
    
    void handleHit(
        in float3 refWp, in float3 refNormal, in float3 lightVector, in bool doTargetLight, in float4 targetColor, in float3 targetWp , in RTOUT hitPosition, 
        inout float3 sky, inout float4 bestRay, inout float sumAO, inout int hits, inout float4 mergedGiColor,
        in float3 rand, in out float missRays
    ) {
        
        float3 coords = getScreenPosition(refWp);
        float2 pixelSize = ReShade::PixelSize;
        float3 screenCoords = getScreenPosition(hitPosition.wp);
        
        float4 giColor = 0.0;
        
        if(isSky(screenCoords.z)) {
        	hitPosition.status = RT_HIT_SKY;
        }
        
        if(!inScreen(screenCoords.xy) || hitPosition.status == RT_MISSED_FAST) {

        } else if(hitPosition.status <= RT_MISSED) {
            if(doTargetLight) {
                giColor = getRayColor(screenCoords.xy);
                
                float hitB = getBrightness(giColor.rgb);
                float targetB = getBrightness(targetColor.rgb);
                if(hitB<targetB && targetB>0.3) {
					missRays += targetB;
	                if(targetB>=bestRay.a) {
	                	bestRay = float4(screenCoords,targetB);
					} 
                    
                }
                giColor = 0;
            }
            
        } else if(hitPosition.status==RT_HIT_SKY) {
            giColor = doTargetLight ? targetColor : getRayColor(screenCoords.xy);
            float b = getBrightness(giColor.rgb);
            if(b>0) {
                sky = max(sky,giColor.rgb);
            }
            
            hits++;
            sumAO+=1;
            
        } else if(hitPosition.status>=0 ) {
        
            float mul = 1;
            float b = 1;
        
            float dist = distance(hitPosition.wp,refWp);
            bool behind = hitPosition.status==RT_HIT_BEHIND;
                
            if(behind) {

                //giColor = float3(0,0,1);
                if(doTargetLight) {
                    giColor = getRayColor(screenCoords.xy);
                    
                    float hitB = getBrightness(giColor.rgb);
                    float targetB = getBrightness(targetColor.rgb);
                    if(hitB<targetB && targetB>0.3) {
						missRays += targetB*2; 
		                if(targetB>=bestRay.a) {
		                	bestRay = float4(screenCoords,targetB);
						} 
                    }
                    giColor = 0;
                }
                
            } else {
                bool hitTargetLight = doTargetLight && hitLight(refWp, hitPosition.wp,targetWp);
                if(doTargetLight) {
                    if(hitTargetLight) {
                        giColor = targetColor;
                        
                    } else if(!bDebugLight || !bDebugLightOnly) {
                        giColor = getRayColor(screenCoords.xy);
                        
                        float hitB = getBrightness(giColor.rgb);
                        float targetB = getBrightness(targetColor.rgb);
                        if(hitB<targetB && targetB>0.3) {
							missRays += targetB*2;
			                if(targetB>=bestRay.a) {
			                	bestRay = float4(screenCoords,targetB);
							} 
                        }
                        // hit something before
                    }
                } else {
                    giColor = getRayColor(screenCoords.xy);
                }
                
                if(doTargetLight) {
                    //dist /= 0.5+targetColor.a*screenCoords.z;
                    mul /= max(1.0,pow(fGIDistanceAttenuation,8.0)*30*dist);
            
                    giColor.rgb = RGBtoOKL(giColor.rgb);
                    giColor.x *= mul;
                    giColor.rgb = OKLtoRGB(giColor.rgb);
                }
                
                
                b = getBrightness(giColor.rgb);
                
                if(b>=bestRay.a && !doTargetLight) {
                    bestRay = float4(screenCoords,b);
                }
                
            }

			float4 DRTF = getDRTF(screenCoords.xy);  
            if((dist>0 || doTargetLight) && (fGIAvoidThin==0 || DRTF.z>DRTF.x*100*fGIAvoidThin)) {
                float ao = 2.0*dist/(iAODistance*screenCoords.z*getDepthMultiplier());
                if(doTargetLight) {
                    float maxDist = distance(targetWp,refWp);
                    ao = min(ao,lerp(1,safePow(dist/maxDist,10),b));
                }
                sumAO += saturate(ao);
                hits+=1.0;
            }
            
            
            mergedGiColor.rgb = max(mergedGiColor.rgb,giColor.rgb);
            mergedGiColor.a = getBrightness(mergedGiColor.rgb);
        }
    }
    
    float2 nextRand2(float2 rand) {
        return  normalize(frac(abs(rand)*PI)-0.5)*2;
    }
    float3 nextRand3(float3 rand) {
        return  normalize(frac(abs(rand)*PI)-0.5)*2;
    }

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outBestRay : SV_Target1) {
        
        if(!isScaledProcessed(coords)) {
        	outGI = float4(0,0,0,1);
            outBestRay = float4(0,0,0,1);
            return;            
        }
        float2 scaledCoords = coords/fGIRenderScale;
        
        int subWidth = 1.0/fGIRenderScale;
        int subMax = subWidth*subWidth;
        int subCoordsIndex = framecount%subMax;
        
        float depth = getDepth(scaledCoords);
        if(isSky(depth)) {
            outGI = float4(0,0,0,1);
            outBestRay = float4(scaledCoords,depth,fSkyColor);
            return;
        }
        
        
        float3 refWp = getWorldPosition(scaledCoords,depth);
        float3 refNormal = getNormal(scaledCoords);
        float3 refColor = getColor(scaledCoords).rgb;
        
        float3 screenCoords;
        
        float4 bestRay = getColorSampler(previousBestRaySampler,coords);
        bestRay.a = 0;

        float3 sky = 0.0;
        float4 mergedGiColor = 0.0;     
        
        float sumAO = 0;
        float hits = 0;
        float missRays = 0;
        int rays = 0;
        
        float2 subCoords = scaledCoords;
        
#if TEX_NOISE
        float3 rand = randomTriple(subCoords+0.05*framecount);
#else
        uint seed = getPixelIndex(subCoords,RENDER_SIZE);
        float3 rand = randomTriple(subCoords,seed);
#endif
        

        int maxRays = iRTMaxRays*(iRTMaxRaysMode?subMax:1);
        int raysLimit = maxRays+4;
        if(bDebugLight) {
            maxRays = bDebugLightOnly ? 1 : maxRays+1;
        }
        
        [loop]
        for(rays=0;rays<maxRays;rays++) {
            
            if(fGIRenderScale<1.0) {
                subCoordsIndex = (subCoordsIndex+1)%subMax;
                int2 delta = 0;
                delta.x = subCoordsIndex%subWidth;
                delta.y = subCoordsIndex/subWidth;
                subCoords = scaledCoords+ReShade::PixelSize*(delta-subWidth*0.5);
                depth = getDepth(subCoords);
                refWp = getWorldPosition(subCoords,depth);
                refNormal = getNormal(subCoords);
            }
            
           
            bool doTargetLight = bDebugLight && rays==0;
            rand = nextRand3(rand);
            rand = normalize(rand-0.5);

            float3 targetWp;
            float4 targetColor;
            float3 lightVector;
            float3 shadowColor;
            if(doTargetLight) {
                targetWp = !bDebugLight ? getWorldPosition(bestRay.xy,bestRay.z) : getDebugLightWp();           
                targetWp += rand*iDebugLightSize*0.9;
                lightVector = normalize(targetWp-refWp);
                targetColor = !bDebugLight ? getColorSampler(rayColorSampler,bestRay.xy) :  float4(fDebugLightColor,1);
            } else {
                lightVector = rand;
                lightVector += cross(rand,refNormal);
                lightVector += refNormal;
            }

            RTOUT hitPosition = trace(refWp,lightVector,false,doTargetLight,targetWp);
            if(!bDebugLightOnly && hitPosition.status==RT_MISSED_FAST && maxRays<raysLimit) {
                maxRays+=1;
            }
            
            handleHit(
                refWp, refNormal, lightVector, doTargetLight, targetColor,targetWp, hitPosition, 
                sky, bestRay, sumAO, hits, mergedGiColor,
                rand,missRays
            );
            
            if(doTargetLight) {
                bestRay.a *= 0.1;
            }

        }

        mergedGiColor.rgb = max(mergedGiColor.rgb,sky);
        float ao = hits>0 ? saturate(sumAO/hits) : 1.0;
        
        outBestRay = bestRay;
        outGI = float4(mergedGiColor.rgb,ao);
    }
    
    float getBorderProximity(float2 coords) {
        float2 borderDists = min(coords,1.0-coords)*BUFFER_SIZE;
        float borderDist = min(borderDists.x,borderDists.y);
        return borderDist<=iHudBorderProtectionRadius ? float(iHudBorderProtectionRadius-borderDist)/iHudBorderProtectionRadius : 0;
    }
    
    void PS_GIFill(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outBestRay : SV_Target) {

        if(!isScaledProcessed(coords)) {
            outBestRay = float4(0,0,0,1);
            return;            
        }
        //float2 scaledCoords = getUpscaledCoords(coords);

        float2 pixelSize = ReShade::PixelSize;
        float4 bestRay = getColorSampler(bestRaySampler,coords);
        
#if TEX_NOISE
        float3 rand = randomTriple(coords+0.05*framecount);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);
        float3 rand = randomTriple(coords,seed);
#endif

        int2 delta;         
        int2 res = floor(RENDER_SIZE/RESV_SCALE);
        int maxDist = 8;
        int count = 0;
        for(delta.x=-maxDist;delta.x<=maxDist;delta.x+=2) {
            for(delta.y=-maxDist;delta.y<=maxDist;delta.y+=2) {
                count++;
                float d = length(delta);
                if(d>maxDist) continue;
                
                float2 currentCoords = coords + delta*pixelSize*d;
                rand = nextRand3(rand);
                currentCoords += cos(rand.xy*2*PI)*0.07*fGIRenderScale;
                if(!isScaledProcessed(currentCoords)) continue;
                
                float4 ray = getColorSampler(bestRaySampler,currentCoords);                 
                if(ray.a>bestRay.a) {
                    bestRay = ray;
                }
            }
        }

        outBestRay = bestRay;
        
    }
    
    void PS_GILightPass2(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outBestRay : SV_Target1) {

        if(!isScaledProcessed(coords)) {
        	outGI = float4(0,0,0,1);
            outBestRay = float4(0,0,0,1);
            return;            
        }
        float2 scaledCoords = coords/fGIRenderScale;

        float depth = getDepth(scaledCoords);
        if(isSky(depth)) {
            outGI = float4(0,0,0,1);
            outBestRay = float4(scaledCoords,depth,fSkyColor);
            return;
        }   
     
        float2 previousCoords = getPreviousCoords(scaledCoords);
        float2 previousCoordsScaled = previousCoords*fGIRenderScale;
        
        float4 firstPassFrame = getColorSampler(giPassSampler,coords);
                
        float3 refWp = getWorldPosition(scaledCoords,depth);
        float3 refNormal = getNormal(scaledCoords);
        float3 refColor = getColor(scaledCoords).rgb;
        
        float3 screenCoords;
        
        float firstAO = firstPassFrame.a;
        float4 mergedGiColor = firstPassFrame;
        
        mergedGiColor.a = getBrightness(mergedGiColor.rgb);
        
        float hits = 0;
        float sumAO = 0;
        
        float3 sky = 0.0;
        float4 bestRay;// = getColorSampler(bestRayFillSampler,previousCoords);        
        
        int rays = 0;
        float missRays = 0;
        
        float2 subCoords = coords;
                                  
        
#if TEX_NOISE
        float3 rand = randomTriple(subCoords+0.05*framecount);
#else
        uint seed = getPixelIndex(subCoords,RENDER_SIZE);
        float3 rand = randomTriple(subCoords,seed);
#endif
        float2 pixelSize = ReShade::PixelSize/fGIRenderScale;
        
        if(!(bDebugLight && bDebugLightOnly)) {
			
            bestRay = getColorSampler(bestRayFillSampler,previousCoordsScaled);
            bestRay.a = 0;
            
            float3 targetCoords = bestRay.xyz;
            float4 targetColor = getRayColor(targetCoords.xy);
            
            targetCoords.xy +=  2*pixelSize*rand.yz;
            targetCoords.z = getDepth(targetCoords.xy);
            targetColor = getRayColor(targetCoords.xy);
        	
            
            targetCoords.z = getDepth(targetCoords.xy);
            
            float3 targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
            targetWp += (rand-0.5)*8*(1+fHudBorderProtectionStrength*getBorderProximity(targetCoords.xy));
            
            float3 lightVector = normalize(targetWp-refWp);
            
            RTOUT hitPosition = trace(refWp,lightVector,false,true,targetWp);
            handleHit(
                refWp, refNormal, lightVector, true, targetColor, targetWp, hitPosition, 
                sky, bestRay, sumAO, hits, mergedGiColor,
                rand,missRays
            );
            rays++;
                
            
#if !DX9_MODE
            float2 step = 1.0/(1+iMemRadius);
            step.y *= float(BUFFER_WIDTH)/BUFFER_HEIGHT;
            
            float2 searchCoords = 0;
            float dist = 0;
            
            float currentIndex = 0;
            for(searchCoords.y=step.y*0.5;searchCoords.y<=1.0-step.y*0.5;searchCoords.y+=step.y) {
                for(searchCoords.x=step.x*0.5;searchCoords.x<=1.0-step.x*0.5;searchCoords.x+=step.x) {
                    rays++;
        #if TEX_NOISE
                    rand = (randomCouple(subCoords+(0.05*(rays+framecount)))-0.5);
        #else
                    rand = (randomTriple(subCoords,seed).xy-0.5);
        #endif

                    float2 currentCoords = searchCoords+step*rand.xy;
                    
                    if(!inScreen(currentCoords)) continue;
                    
					currentCoords = getColorSampler(bestRayFillSampler,currentCoords*fGIRenderScale).xy;
    
                    float3 targetCoords = float3(currentCoords,getDepth(currentCoords));
                    
                    float3 targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
                    
                    targetWp += rand*8*fHudBorderProtectionStrength*getBorderProximity(targetCoords.xy);
                    targetCoords.xy = getScreenPosition(targetCoords).xy;
                    
                    float3 lightVector = normalize(targetWp-refWp);
                    
                    
                    targetCoords = getScreenPosition(targetWp);
                    if(!inScreen(targetCoords.xy)) {
                        continue;
                    }
                    
                    float3 targetNormal = getNormal(targetCoords.xy);
                    if(!isSky(targetCoords.z) && length(targetNormal+lightVector)>1.4) {
                        continue;
                    }
                    
                    
                    float diff = maxOf3(abs(targetNormal-refNormal));
                    if(diff<0.8) {
                        hits++;
                        continue;
                    }
                    
                    RTOUT hitPosition = trace(refWp,lightVector,false,true,targetWp);
                    
                    float4 targetColor = getRayColor(targetCoords.xy);
                    handleHit(
                        refWp, refNormal, lightVector, true, targetColor, targetWp, hitPosition, 
                        sky, bestRay, sumAO, hits, mergedGiColor,
                        rand,missRays
                    );
                    
                    
                    
                }
                
                
            }
            
#endif
        }
        
        sumAO += firstAO*iRTMaxRays;
	    hits += iRTMaxRays;
        float ao = hits>0 ? sumAO/hits : 1;
        
        	
    	if(missRays>0) {
			ao /= missRays;
   	 }
        
        mergedGiColor.rgb = max(mergedGiColor.rgb,sky);
        mergedGiColor.rgb = max(mergedGiColor.rgb,firstPassFrame.rgb);		
        outBestRay = float4(bestRay.xyz,1);
        outGI = float4(mergedGiColor.rgb,ao);
        
        
    }

// SSR
    float3 computeSSR(float2 coords,float brightness) {
        float4 ssr = getColorSamplerLod(ssrAccuSampler,coords,1);
        if(ssr.a==0) return 0;
        
        
        
        float3 ssrHSV = RGBtoHSV(ssr.rgb);
        
        float ssrBrightness = getBrightness(ssr.rgb);
        float ssrChroma = ssrHSV.y;
        
        float colorPreservation = lerp(1,safePow(brightness,2),1.0-safePow(1.0-brightness,10));
        
        ssr = lerp(ssr,ssr*0.5,saturate(ssrBrightness-ssrChroma));
        
        float roughness = getRTF(coords).x;
        
        float rCoef = lerp(1.0,saturate(1.0-roughness*10),fSSRMergingRoughness);

        float coef = fSSRMerging*(1.0-brightness)*rCoef;

        if(fSSRMergingOrientation>0) {
            float3 normal = getNormal(coords);
            float3 preferedOrientation = normalize(float3(0,-1,-0.5));
            float oCoef = saturate(dot(normal,preferedOrientation));
            coef *= (1.0-fSSRMergingOrientation)+lerp(1,oCoef,fSSRMergingOrientation)*fSSRMergingOrientation;
        }

        return ssr.rgb*coef;
            
    }

    void PS_SSRLightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!bSSR || fSSRMerging==0.0) {
            outColor = 0.0;
            return;
        }
        
        if(coords.x>fSSRRenderScale || coords.y>fSSRRenderScale) {
        	outColor = float4(0,0,0,1);
        	return;
        }
        
        coords /= fSSRRenderScale;
        
        int subWidth = min(4,ceil(1.0/fSSRRenderScale));
        int subMax = subWidth*subWidth;
        int subCoordsIndex = framecount%subMax;
        int2 delta = 0;
        
        float2 subCoords = coords;
        
        if(!bSSRHQSubPixel && fSSRRenderScale<1.0) {
            delta.x = subCoordsIndex%subWidth;
            delta.y = subCoordsIndex/subWidth;
            subCoords = coords+ReShade::PixelSize*(delta-subWidth*0.5);
        }
            
        float depth = getDepth(subCoords);
        
        if(isSky(depth)) {
            outColor = 0.0;
        } else {
        
            float3 result = 0;
            float weightSum = 0;
            
            [loop]
            for(int rays=0;rays<(bSSRHQSubPixel && fSSRRenderScale<1.0 ?subMax:1);rays++) {
                
                if(bSSRHQSubPixel && fSSRRenderScale<1.0) {
                    subCoordsIndex = (framecount+rays)%subMax;
                    delta.x = subCoordsIndex%subWidth;
                    delta.y = subCoordsIndex/subWidth;
                    subCoords = coords+ReShade::PixelSize*(delta-subWidth*0.5);
                    depth = getDepth(subCoords);
                }
                
                float3 targetWp = getWorldPosition(subCoords,depth); 
                float3 targetNormal = getNormal(subCoords);
                               
                float3 lightVector = normalize(reflect(targetWp,targetNormal));
                
                RTOUT hitPosition = trace(targetWp,lightVector,true,false,0);
                
                
                float3 screenPosition = getScreenPosition(hitPosition.wp.xyz);
                    
                if(hitPosition.status<RT_HIT_SKY) {
                    
                } else {
                    //float3 screenPosition = getScreenPosition(hitPosition.wp.xyz);
                    float depth = getDepth(screenPosition.xy);
                    if(hitPosition.status==RT_HIT_BEHIND) {
                        weightSum += 1;
                    } else {
                        float2 previousCoords = getPreviousCoords(screenPosition.xy);
                        float3 hitNormal = getNormal(screenPosition.xy);
                        if(distance(hitNormal,targetNormal)<0.2) continue;
                        
                        float3 c = getColorSampler(resultSampler,previousCoords).rgb;
                        if(bSSRRinR) {
							c = max(c,getColorSampler(ssrAccuSampler,previousCoords).rgb*0.8);
                        }

                        float w = getBrightness(c)*100.0+1.0;
                        result += c*w;
                        weightSum += w;
                    }
                
                }
            }

            if(weightSum>0) {
                result /= weightSum;
                outColor = float4(result,getBrightness(result));
            } else {
                outColor= float4(0,0,0,0);
            }
        }
        
            
    }
    
/////////////////////////////////
    
	// Helper functions
	float gaussian(float x, float sigma) {
	    return exp(-(x * x) / (2.0 * sigma * sigma));
	}
	
	float calculateDepthWeight(float centerDepth, float sampleDepth, float sigma) {
	    float diff = abs(centerDepth - sampleDepth);
	    return gaussian(diff, sigma);
	}
    
    
///////////////////////////////////
    
    void smooth(
        sampler sourceGISampler,
        float2 coords, out float4 outGI, bool firstPass
    ) {
        float2 pixelSize = ReShade::PixelSize;
        
        if(firstPass && !isScaledProcessed(coords)) {
        	outGI = float4(0,0,0,1);
            return;            
        }
        

        
        
        float2 scaledCoords = firstPass ? coords/fGIRenderScale : coords;
        
        
        float refDepth = getDepth(scaledCoords);
        if(isSky(refDepth)) {
            outGI = float4(getColor(scaledCoords).rgb,1);
            return;
        }
                

        
        float2 downscaledCoords = firstPass ? coords : coords*fGIRenderScale;
        
        float2 previousCoords = getPreviousCoords(scaledCoords);
        float previousDist = distance(scaledCoords*BUFFER_SIZE,previousCoords*BUFFER_SIZE);
        float4 previousAccu = getColorSampler(giPreviousAccuSampler,previousCoords);
        	
        //float previousDepth = getColorSamplerLod(previousDepthSampler,coords,1).x;
        float3 refNormal = getNormal(scaledCoords);  
        float3 refWp = getWorldPosition(scaledCoords,refDepth);        
        
        float2 weightSum;
        
        float4 giAo = 0.0;
        
        float2 currentCoords;                        
        int2 delta;
        float avgB = getAverageBrightness();
        
        float roughness = getRTF(scaledCoords).x;
            
        float maxSamples = iSmoothSamples;
        float3 previousResult = 0;
        
        float radius = iSmoothRadius;
        if(firstPass) {
	        radius = 6;
	    
        } else {
        	radius = iSmoothRadius;
        	float4 bestRay = getColorSampler(bestRaySampler,coords*fGIRenderScale);
    		float3 bestRayWp = getWorldPosition(bestRay.xy,bestRay.z);
    		float dist = distance(refWp,bestRayWp);
	    	radius += (dist*0.35);
	    	//radius = min(radius,32*(1.0-refDepth));
        }
        
    	        
#if TEX_NOISE
        float3 rand = randomTriple(coords+0.05*framecount);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);
        float3 rand = randomTriple(coords,seed);
#endif
    	float angle = rand.x*2*PI;
    	
        [loop]
        for(float s=0;s<maxSamples;s+=1.0) {
			angle += PI/4.0;
            currentCoords = downscaledCoords+float2(cos(angle),sin(angle))*pixelSize.xy*radius*pow(s/maxSamples,2);

            if(!isScaledProcessed(currentCoords)) continue;
            
            float2 currentScaledCoords = currentCoords/fGIRenderScale;
            
            float depth = getDepth(currentScaledCoords);
            if(isSky(depth)) {
#if DX9_MODE
                continue;
#else
                depth = getColorSampler(previousDepthSampler,coords).x;
                if(isSky(depth)) {
                    continue;
                }
#endif
            }
            
            
            // Distance weight
            float2 weight = 1.0;   
            
            float nw = 0;
            // Normal weight
            {
                float3 normal = getNormal(currentScaledCoords);
                float d = dot(normal,refNormal);
                nw = saturate(d);
                nw = pow(nw,3.0/fGIRenderScale);
				weight.x *= nw;
				weight.y *= saturate(d);
            }
            
            {
	            float diffDepth = abs(depth - refDepth);
	            weight *= max(0.001,1.0-100*diffDepth*saturate(1.0-refDepth*2.0));
            }
            
            if(weight.x>0) {
                float4 curGiAo = getColorSampler(sourceGISampler,currentCoords);
                curGiAo.rgb = RGBtoOKL(curGiAo.rgb);
                weight.x *= avgB+curGiAo.x;

				float3 wp = getWorldPosition(currentScaledCoords,depth);
				float d = distance(refWp,wp);
				if(d>iAODistance*0.5) weight.y = 0;
                
                giAo.rgb += curGiAo.rgb*weight.x;
                giAo.a += curGiAo.a*weight.y;
                
	                
            }
            
            weightSum += weight;
            
            float3 result = giAo.rgb/weightSum.x;
            if(maxOf3(abs(result-previousResult))>0.05) {
                maxSamples = min(maxSamples+1,iSmoothSamples*2);
            }
            previousResult = result;
            
        }
        
        if(weightSum.x>0) {
            giAo.rgb /= weightSum.x;
            
            previousAccu.rgb = RGBtoOKL(previousAccu.rgb);
	        giAo.rgb = lerp(giAo.rgb,previousAccu.rgb,0.5);
	        
	        giAo.rgb = OKLtoRGB(giAo.rgb);
			

        } else {
            giAo.rgb = 0;
        }
        
        if(weightSum.y>0) {
            giAo.a /= weightSum.y;
            giAo.a = lerp(giAo.a,previousAccu.a,0.5);
        } else {
            giAo.a = 1.0;
        }
        
        outGI = giAo;
    }
    
    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        smooth(giPass2Sampler,coords,outGI, true);
    }
    
    void PS_Smooth2Pass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        smooth(giSmoothPassSampler,coords,outGI, false);
    }
    
    float3 oklLerp(float3 a,float3 b, float3 r) {
    	return OKLtoRGB(lerp(RGBtoOKL(saturate(a)),RGBtoOKL(saturate(b)),r));
    }
    
    
    void PS_AccuPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {

        
        float4 giAO = getColorSampler(giSmooth2PassSampler,coords);
        float4 ssr = 0;
        

        float2 op = 1.0/float2(iGIFrameAccu,iAOFrameAccu);
        
        float roughness = getRTF(coords).x;
        op *= max(0.5,saturate(1.0-roughness*5.0));
            
        float3 color = getColor(coords).rgb;
        
        float2 previousCoords = getPreviousCoords(coords);    
        float motionDist = 1+distance(coords*BUFFER_SIZE,previousCoords*BUFFER_SIZE);
		float centerDist = distance(0.5*BUFFER_SIZE,previousCoords*BUFFER_SIZE);
		motionDist *= (1+centerDist*50.0/BUFFER_WIDTH);
        
        op = lerp(op,1,saturate(motionDist/256)); 

        op = saturate(op);
        
        
        
        float4 previousColorMoved = getColorSampler(giPreviousAccuSampler,previousCoords);
        float3 colorDist = abs(previousColorMoved.rgb-giAO.rgb);
        
        float pb = getBrightness(previousColorMoved.rgb);        
		giAO.rgb = pb>0 ? oklLerp(previousColorMoved.rgb,giAO.rgb,op.x) : giAO.rgb;
        giAO.a = pb>0 ? lerp(previousColorMoved.a,giAO.a,op.y) : giAO.a;
        

        if(bSSR) {
        	
            ssr = getColorSampler(ssrPassSampler,coords*fSSRRenderScale);
            if(ssr.a<0.1) {
                float4 precision = tex2DgatherA(ssrPassSampler,coords);
                float m = maxOf3(precision.xyz);
                if(precision.x==m) ssr = max(ssr,getColorSampler(ssrPassSampler,coords*fSSRRenderScale+float2(0,ReShade::PixelSize.y)));
                else if(precision.y==m) ssr = max(ssr,getColorSampler(ssrPassSampler,coords*fSSRRenderScale+ReShade::PixelSize));
                else if(precision.z==m) ssr = max(ssr,getColorSampler(ssrPassSampler,coords*fSSRRenderScale+float2(ReShade::PixelSize.x,0)));
            }
            
        
            float4 previousSSRm = getColorSampler(ssrPreviousAccuSampler,previousCoords);
            float4 previousSSR = getColorSampler(ssrPreviousAccuSampler,coords);
            previousSSRm = lerp(previousSSRm,previousSSR,0.5);
            
            float op = ssr.a/iSSRFrameAccu;
            float refDepth = getDepth(coords);
            op = max(0.33/iSSRFrameAccu,op*saturate(1.0-refDepth*3));
            
            op = lerp(op,1,saturate(motionDist/256));           
            op = saturate(op);
            if(maxOf3(previousSSRm)<0.01) op = 1;
            
            ssr.rgb = oklLerp(
                    previousSSRm.rgb,
                    ssr.rgb,
                    op
                );
        }
        
        outGI = giAO;
        outSSR = ssr;
    }
    
    
    float smoothPow(float x,float p) {
    	return smoothstep(0,1,pow(x,p));
    }
    
    
    float computeAo(float ao,float colorBrightness, float giBrightness, float avgB) {
        
        //ao = fAOMultiplier-(1.0-ao)*fAOMultiplier;
        if(fAOBoostFromGI>0) {
			//ao *= pow(giBrightness,fAOBoostFromGI*4);
			ao -= fAOBoostFromGI*pow(1.0-giBrightness,2);
        }
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        
        ao = (safePow(ao,fAOPow));
        
        //ao += giBrightness*fAoProtectGi*4.0;
        
        float inDark = max(0.1,pow(avgB,0.25));
        ao += (1.0-colorBrightness)*(1.0-colorBrightness)*fAODarkProtect;
        ao += pow(colorBrightness,2)*fAOLightProtect;
        
        ao = saturate(ao);
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        //ao += pow(giBrightness,2.0)*(1.0-fAoProtectGi)*4.0;
        ao += pow(giBrightness,2.0)*fAoProtectGi*4.0;
        
        ao += saturate((1.0-colorBrightness)*fAODarkProtect/inDark);
        
        return saturate(ao);
    }
    


    float3 compureResult(
            in float2 coords,
            in float depth,
            in float3 refColor,
            in float4 giAo,
            in bool reinhardFirstPass
        ) {

        float3 color = refColor;
         
        float originalColorBrightness = maxOf3(color);

        if(bRemoveAmbient) {
            color = filterAmbiantLight(color);
        }
        
        
        float3 gi = giAo.rgb;
        
        float3 giHSV = RGBtoHSV(gi);
        float3 colorHSV = RGBtoHSV(color);
       
        float colorBrightness = getBrightness(color);
            
        // Base color
        float3 result = color*(bBaseAlternative?1.0:fBaseColor);
        
        
        
        // GI
        float avgB = getAverageBrightness();

        result += originalColorBrightness*gi*fGIDarkMerging*(1.0-pow(originalColorBrightness,0.2));
        
        if(fGIHueBiais>0) {
            float3 c = colorHSV;
            c.xy = giHSV.xy;
            c = HSVtoRGB(c);
            result = oklLerp(result,c,saturate(2*fGIHueBiais*giHSV.y*giHSV.z*saturate(1.0-colorHSV.y*colorHSV.z*4.0)));
        }
        
        float giBrightness =  getBrightness(gi);            
        
        result += pow(result,0.25)*gi*saturate(1.0-avgB)*fGIDarkMerging*(1.0-originalColorBrightness*(1.0-fGILightMerging));        
        
        // Overbright
        if(!reinhardFirstPass && fGIOverbrightToWhite>0) {
            float b = maxOf3(result);
            if(b>1) {
                result += (b-1)*fGIOverbrightToWhite;
            }
        }
        
        
        if(bRreinhardFinalMerging && !reinhardFirstPass) {
            float2 mMW = getColorSampler(reinhardSampler,CENTER).xy;
            float3 rResult = result*(1+result/(mMW.y*mMW.y))/(1+result);
            result = oklLerp(result,rResult,fRreinhardStrength);
        }
        
        return reinhardFirstPass ? result : oklLerp(refColor,saturate(result),getRTF(coords).a);
        //return color;
    }
    

    void PS_ReinhardPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outReinhard : SV_Target0) {
        if(!bRreinhardFinalMerging) discard;
        float2 minMaxW = 0;
        
        float2 currentCoords = 0;
        float2 rand = randomCouple(coords);
        
        float2 pixelSize = ReShade::PixelSize;
        float2 stepSize = (BUFFER_SIZE/8.0)*pixelSize;
        
        for(currentCoords.x=stepSize.x*0.5;currentCoords.x<=1.0-stepSize.x*0.5;currentCoords.x+=stepSize.x) {
            for(currentCoords.y=stepSize.y*0.5;currentCoords.y<=1.0-stepSize.y*0.5;currentCoords.y+=stepSize.y) {
                rand = nextRand2(rand);
                float2 c = currentCoords+(rand-0.5)*stepSize;
               
                float depth = getDepth(c);
                float3 refColor = getColor(c).rgb;
                
                float4 giAo = getColorSampler(giAccuSampler,c);
               
                float3 result = compureResult(c,depth,refColor,giAo,true);
                float b = getBrightness(result);
                minMaxW.x = min(minMaxW.x,b);
                minMaxW.y = max(minMaxW.y,b);
            }
        }
        
        outReinhard = float4(minMaxW,1.0,1.0/64.0);
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, 
            out float4 outResult : SV_Target,
            out float4 outGiAccu : SV_Target1,
            out float4 outSsrAccu : SV_Target2
#if !DX9_MODE
            ,out float4 outColor : SV_Target3,
            out float4 outDepth : SV_Target4
#endif
    ) {
        float depth = getDepth(coords);
        float3 refColor = getColor(coords).rgb;

        float4 giAo = getColorSampler(giAccuSampler,coords);

        outGiAccu = giAo;
        outSsrAccu = bSSR ? getColorSampler(ssrAccuSampler,coords) : 0;
#if !DX9_MODE
        outDepth = depth;
        outColor = float4(refColor,1);
#endif

        outResult = float4(compureResult(coords,depth,refColor,giAo,false),1.0);
    }
    

    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
    {        
        float3 result = 0;
        if(bDebugLight) {
            if(distance(coords,fDebugLightPosition.xy)<2*ReShade::PixelSize.x) {
                float colorBrightness = getBrightness(result);
                float3 ssr = computeSSR(coords,colorBrightness);
                outPixel = float4(fDebugLightColor,1);
                return;
            }
        }
        
        
        if(iDebug==DEBUG_OFF) {
            result = getColorSampler(resultSampler,coords).rgb;
            
            // AO
    		float avgB = getAverageBrightness();
            float resultB = getBrightness(result);
            float4 giAo = getColorSampler(giAccuSampler,coords);
            float giBrightness = getBrightness(giAo.rgb);
			float ao = giAo.a;
            ao = computeAo(ao,resultB,giBrightness,avgB);
            result *= ao;
               
            // SSR
            if(bSSR && fSSRMerging>0.0) {
                float colorBrightness = getBrightness(result);
                float3 ssr = computeSSR(coords,colorBrightness);
                result += ssr;
            }
            
            // Levels
            result = (result-iBlackLevel/255.0)/((iWhiteLevel-iBlackLevel)/255.0);
            
            // Distance fading
            float depth = getDepth(coords);
            if(fDistanceFading<1.0 && depth>fDistanceFading*getDepthMultiplier()) {
                float3 color = getColor(coords).rgb;
            	
				float diff = depth/getDepthMultiplier()-fDistanceFading;
                float max = 1.0-fDistanceFading;
                float ratio = diff/max;
                result = result*(1.0-ratio)+color*ratio;
            }
            
            result = saturate(result);
            
        } else if(iDebug==DEBUG_GI) {
            float4 passColor;
            if(iDebugPass==0) passColor =  getColorSampler(giPassSampler,coords*fGIRenderScale);
            //if(iDebugPass==0) passColor =  getColorSampler(giPass2Sampler,coords*fRenderScale);
            if(iDebugPass==1) passColor =  getColorSampler(giPass2Sampler,coords*fGIRenderScale);
            //if(iDebugPass==1) passColor =  getColorSampler(giSmoothPassSampler,coords*fRenderScale);
            if(iDebugPass==2) passColor =  getColorSampler(giSmooth2PassSampler,coords);
            //if(iDebugPass==2) passColor =  getColorSampler(giSmoothPassSampler,getDownscaledCoords(coords));
            if(iDebugPass>=3) passColor =  getColorSampler(giAccuSampler,coords);

            result = passColor.rgb;
            if(iDebugPass==4) {
                float3 gi = result;
                float3 refColor = getColor(coords).rgb;
                float3 color = refColor; 

                if(bRemoveAmbient) {
                    color = filterAmbiantLight(color);
                }

                float colorBrightness = getBrightness(color);
                float3 colorHSV = RGBtoHSV(color);
                
                float3 giHSV = RGBtoHSV(gi);          
            
                float3 tintedColor = colorHSV;
                tintedColor.xy = gi.xy;
                tintedColor = HSVtoRGB(tintedColor);
                //hb += saturate(1.0-colorHSV.y-0.6)*(max(1.0-colorHSV.z,colorHSV.z))*2;
                float avgB = getAverageBrightness();
                
                result = color;
                
                if(fGIHueBiais>0 && giHSV.y>0 && giHSV.z>0) {
                    float3 c = gi;
                    c *= colorBrightness/giHSV.z;
                    result = lerp(result,c,saturate(fGIHueBiais*4*giHSV.y*(1.0-giHSV.z)));
                }
                
                float3 addedGi = gi*color*
                    saturate(
                    (pow(1.0-colorBrightness,2)-pow(1.0-colorBrightness,4))*2*fGIDarkMerging
                    -(pow(colorBrightness,2)-pow(colorBrightness,4))*(1.0-fGILightMerging)
                    )*fGIFinalMerging;
                    
                result += addedGi;
                
                result = saturate(0.5+result-color);
            }

            
        } else if(iDebug==DEBUG_AO) {

            float4 passColor;
            if(iDebugPass==0) passColor =  getColorSampler(giPassSampler,coords*fGIRenderScale);
            if(iDebugPass==1) passColor =  getColorSampler(giPass2Sampler,coords*fGIRenderScale);
           // if(iDebugPass==1) passColor =  getColorSampler(giSmoothPassSampler,coords*fRenderScale);
            if(iDebugPass==2) passColor =  getColorSampler(giSmooth2PassSampler,coords);
            if(iDebugPass>=3) passColor =  getColorSampler(giAccuSampler,coords);

            float ao = passColor.a;
            
            
            if(iDebugPass==3) {
	            float giBrightness = getBrightness(passColor.rgb);
				if(fAOBoostFromGI>0) {
					//ao *= pow(giBrightness,(fAOBoostFromGI)*4);
					ao -= fAOBoostFromGI*pow(1.0-giBrightness,2);
		        }
                ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        		ao += pow(giBrightness,2.0)*fAoProtectGi*4.0;
        		
            } else if(iDebugPass==4) {
                float giBrightness = getBrightness(passColor.rgb);

                float3 color = getColor(coords).rgb;
                if(bRemoveAmbient) {
                    color = filterAmbiantLight(color);
                }
                float colorBrightness = getBrightness(color);
            
                float avgB = getAverageBrightness();
                ao = computeAo(ao,colorBrightness,giBrightness,avgB);
            }
            result = ao;
            
        } else if(iDebug==DEBUG_SSR) {
            float4 passColor;
            if(iDebugPass==0) passColor =  getColorSampler(ssrPassSampler,coords*fSSRRenderScale);
            if(iDebugPass==1) passColor =  getColorSampler(ssrPassSampler,coords*fSSRRenderScale);
            if(iDebugPass==2) passColor =  getColorSampler(ssrPassSampler,coords*fSSRRenderScale);
            if(iDebugPass>=3) passColor =  getColorSamplerLod(ssrAccuSampler,coords,1);
            
            if(iDebugPass==4) {
                float3 color = getColorSampler(resultSampler,coords).rgb;
                float colorBrightness = getBrightness(color);
                passColor = computeSSR(coords,colorBrightness);
            }
            result = passColor.rgb;
            
        } else if(iDebug==DEBUG_ROUGHNESS) {
            float3 RTF = getColorSampler(RTFSampler,coords).xyz;
            
            result = RTF.x;
            //result = RTF.z;
        } else if(iDebug==DEBUG_DEPTH) {
            float depth = getDepth(coords);
            result = depth;
            if(depth<fWeaponDepth*getDepthMultiplier()) {
                result = float3(1,0,0);
            }
            else if(depth==1) {
                result = float3(0,1,0);
            }
            
        } else if(iDebug==DEBUG_NORMAL) {
            result = getColorSampler(normalSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_SKY) {
            float depth = getDepth(coords);
            result = isSky(depth)?1.0:0.0;
            //result = getColor(getColorSampler(bestRaySampler,coords).xy).rbg;
            //result = getColorSampler(bestRayFillSampler,coords).xyz;
      
        } else if(iDebug==DEBUG_MOTION) {
            float2  motion = getPreviousCoords(coords);
            motion = 0.5+(motion-coords)*25;
            result = float3(motion,0.5);
            
            
        } else if(iDebug==DEBUG_AMBIENT) {

            if(coords.y>0.95) {
                if(coords.x<0.5) {
                    result = getRemovedAmbiantColor();
                } else {
                    result = getAverageBrightness();
                }
            } else {
                result = getColor(coords).rgb;
            }           
            
        } else if(iDebug==DEBUG_THICKNESS) {
            float4 drtf = getDRTF(coords);
            float4 rtfs = getColorSampler(RTFSampler,coords);
            if(iDebugPass==0) result =  rtfs.x;
            if(iDebugPass==1) result =  rtfs.y;
            if(iDebugPass==2) result =  rtfs.z;
            if(iDebugPass>=3) result =  rtfs.a;
            if(iDebugPass==4) result = drtf.z*0.004;
            
            result = drtf.z*0.004;
            //result = getColorSampler(previousBestRaySampler,coords).rgb;
      
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT <
        ui_label = "DH_UBER_RT 0.20.1";
        ui_tooltip = 
            "_____________ DH_UBER_RT _____________\n"
            "\n"
            " ver 0.20.1 (2025-02-08)  by AlucardDH\n"
#if DX9_MODE
            "         DX9 limited edition\n"
#endif
            "\n"
            "______________________________________";
    > {
#if!DX9_MODE
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SavePreviousAmbientPass;
            RenderTarget = previousAmbientTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_AmbientPass;
            RenderTarget = ambientTex;
        }
#endif
        
        // Normal Roughness
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RTFS_save;
            RenderTarget = previousRTFTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RTFS;
            RenderTarget = RTFTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_NormalPass;
            RenderTarget = normalTex;
            RenderTarget1 = depthTex;
        }

        // GI
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RayColorPass;
            RenderTarget = rayColorTex;
        }
#if SHPERE
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Sphere_save;
            RenderTarget = previousSphereTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SpherePass;
            RenderTarget = sphereTex;
            
            ClearRenderTargets = false;
                        
            BlendEnable = true;
            BlendOp = ADD;
            SrcBlend = SRCALPHA;
            SrcBlendAlpha = ONE;
            DestBlend = INVSRCALPHA;
            DestBlendAlpha = ONE;
        }
#endif
        
        
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_GILightPass;
            RenderTarget = giPassTex;
            RenderTarget1 = bestRayTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_GIFill;
            RenderTarget = bestRayFillTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_GILightPass2;
            RenderTarget = giPass2Tex;
            RenderTarget1 = previousBestRayTex;
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
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Smooth2Pass;
            RenderTarget = giSmooth2PassTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_AccuPass;
            RenderTarget = giAccuTex;
            RenderTarget1 = ssrAccuTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_ReinhardPass;
            RenderTarget = reinhardTex;
            
            ClearRenderTargets = false;
                        
            BlendEnable = true;
            BlendOp = ADD;
            SrcBlend = SRCALPHA;
            SrcBlendAlpha = ONE;
            DestBlend = INVSRCALPHA;
            DestBlendAlpha = ONE;
        }
        
        
        // Merging
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateResult;
            RenderTarget = resultTex;
            RenderTarget1 = giPreviousAccuTex;
            RenderTarget2 = ssrPreviousAccuTex;
#if !DX9_MODE
            RenderTarget3 = previousColorTex;
            RenderTarget4 = previousDepthTex;
#endif            
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }
}
