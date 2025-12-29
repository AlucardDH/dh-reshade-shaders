////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT 0.22.0 (2025-12-29)
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

#ifndef USE_MARTY_LAUNCHPAD_MOTION
 #define USE_MARTY_LAUNCHPAD_MOTION 0
#endif
#ifndef USE_VORT_MOTION
 #define USE_VORT_MOTION 0
#endif

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

#define RT_HIT_LIGHT 2.0
#define RT_HIT 1.0
#define RT_HIT_BEHIND 0.5
#define RT_HIT_GUESS 0.25
#define RT_HIT_SKY -0.5
#define RT_MISSED -1.0
#define RT_MISSED_FAST -2.0

#define PI 3.14159265359
#define SQRT2 1.41421356237

#define BUFFER_SIZE int2(BUFFER_WIDTH,BUFFER_HEIGHT)
#define BUFFER_SIZE3 int3(BUFFER_WIDTH,BUFFER_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE)


// MACROS /////////////////////////////////////////////////////////////////
// Don't touch this
#define getColor(c) saturate(tex2Dlod(ReShade::BackBuffer,float4((c).xy,0,0))*(bBaseAlternative?fBaseColor:1))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4((c).xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4((c).xy,0,0))
#define CENTER float2(0.5,0.5)
#define S_PR MagFilter=POINT;MinFilter=POINT;MipFilter= POINT;AddressU=REPEAT;AddressV=REPEAT;AddressW=REPEAT;
#define S_PM MagFilter=POINT;MinFilter=POINT;MipFilter= POINT;AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR;
#define S_PC MagFilter=POINT;MinFilter=POINT;MipFilter= POINT;AddressU=Clamp;AddressV=Clamp;AddressW=Clamp;
#define CL AddressU=Clamp;AddressV=Clamp;AddressW=Clamp;
#if DX9_MODE
    #define safePow(a,b) pow(a,b)
#endif

//////////////////////////////////////////////////////////////////////////////

#if USE_MARTY_LAUNCHPAD_MOTION
namespace Deferred {
    texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sMotionVectorsTex { Texture = MotionVectorsTex;  };
}
#elif USE_VORT_MOTION
    texture2D MotVectTexVort {  Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort;  };
#else
    texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler sTexMotionVectorsSampler { Texture = texMotionVectors; };
#endif

namespace DH_UBER_RT_0220 {

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
#endif

    texture previousDepthTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG32F; MipLevels = 6;  };
    sampler previousDepthSampler { Texture = previousDepthTex; MinLOD = 0.0f; MaxLOD = 5.0f; };
    
    texture motionMaskTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; MipLevels = 6;  };
    sampler motionMaskSampler { Texture = motionMaskTex; MinLOD = 0.0f; MaxLOD = 5.0f; };

    // Roughness Thickness
    texture previousRTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler previousRTFSampler { Texture = previousRTFTex; };
    texture RTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler RTFSampler { Texture = RTFTex; S_PR};
   
    texture bestRayTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
    sampler bestRaySampler { Texture = bestRayTex; S_PC };
    
    texture bestRayFillTex { Width = BUFFER_WIDTH/RESV_SCALE; Height = BUFFER_HEIGHT/RESV_SCALE; Format = RGBA16F; };
    sampler bestRayFillSampler { Texture = bestRayFillTex; S_PC};
   
#if SHPERE
    texture previousSphereTex { Width = BUFFER_WIDTH/SPHERE_RATIO; Height = BUFFER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler previousSphereSampler { Texture = previousSphereTex;};
    
    texture sphereTex { Width = BUFFER_WIDTH/SPHERE_RATIO; Height = BUFFER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler sphereSampler { Texture = sphereTex;};
#endif

    texture normalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 6; };
    sampler normalSampler { Texture = normalTex; MinLOD = 0.0f; MaxLOD = 5.0f;};

    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
    texture rayColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler rayColorSampler { Texture = rayColorTex; };
    
    texture giPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler giPassSampler { Texture = giPassTex; S_PM};

    texture giPass2Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    //sampler giPass2Sampler { Texture = giPass2Tex; MinLOD = 0.0f; MaxLOD = 5.0f; S_PM };//S_PR
    sampler giPass2Sampler { Texture = giPass2Tex; MinLOD = 0.0f; MaxLOD = 5.0f; AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR; };//S_PR

    texture giSmoothPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f; AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR; };
    
    texture giSmooth2PassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler giSmooth2PassSampler { Texture = giSmooth2PassTex; MinLOD = 0.0f; MaxLOD = 5.0f; AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR; };
    
    texture giAccuTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};
    sampler giAccuSampler { Texture = giAccuTex; AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR;};
    
    texture giPreviousAccuTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;  MipLevels = 6;};
    sampler giPreviousAccuSampler { Texture = giPreviousAccuTex; MinLOD = 0.0f; MaxLOD = 5.0f; AddressU=MIRROR;AddressV=MIRROR;AddressW=MIRROR;};//S_PR  
   
    // SSR texture
    texture ssrPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;  MipLevels = 6;};
    sampler ssrPassSampler { Texture = ssrPassTex; MinLOD = 0.0f; MaxLOD = 5.0f; };//S_PR
          
    texture ssrAccuTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler ssrAccuSampler { Texture = ssrAccuTex; };
    
    texture ssrPreviousAccuTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;  MipLevels = 6;};
    sampler ssrPreviousAccuSampler { Texture = ssrPreviousAccuTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
// Structs
    struct RTOUT {
        float3 wp;
        float status;
        float4 drtf;
        float dist;
    };
    

// Internal Uniforms
    uniform int framecount < source = "framecount"; >;
    uniform int random < source = "random"; min = 0; max = 512; >;

// Parameters

/*
    uniform float fTest <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.01;
    uniform float fTest2 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 0.0; ui_max = 25.0;
        ui_step = 0.001;
    > = 3.0;
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
        ui_min = 1; ui_max = 256;
        ui_step = 1;
    > = 256;
    uniform int iTest2 <
        ui_category="Test";
        ui_type = "slider";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
    > = 4;
    uniform bool bTest <ui_category="Test";> = false;
    uniform bool bTest2 <ui_category="Test";> = false;
    uniform bool bTest3 <ui_category="Test";> = false;
    uniform bool bTest4 <ui_category="Test";> = true;
    uniform bool bTest5 <ui_category="Test";> = true;
    uniform bool bTest6 <ui_category="Test";> = true;
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
    
    uniform int iDepthMode <
        ui_type = "slider";
        ui_category = "Game specific hacks";
        ui_label = "Depth mode (Default=0,CP2077=1,Unity=2)";
        ui_min = 0; ui_max = 2;
        ui_step = 1;
    > = 0;
    
    uniform bool bGrassNormalFix <
        ui_category = "Game specific hacks";
        ui_label = "Thin objects normal up (can improve grass rendering)";
    > = false;
    
    uniform bool bTAAFlicker <
        ui_category = "Game specific hacks";
        ui_label = "Reduce edge flickering (at the cost of some ghosting)";
    > = true;
    
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
    
    uniform float fWeaponDepthCorrection <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "Weapon Depth correction";
        ui_min = 0.001; ui_max = 1.00;
        ui_step = 0.001;
        ui_tooltip = "Define where the weapon ends to prevent it to affect the SSR";
    > = 0.1;

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
    > = 1;
    
    uniform float fRTPrecision <
        ui_type = "slider";
        ui_category = "Common";
        ui_label = "RT Precision";
        ui_min = 0.25; ui_max = 4.0;
        ui_step = 0.1;
        ui_tooltip = "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    
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

    uniform int iGIRenderScale <
        ui_category="GI/AO: 1st Pass (New rays)";
        ui_label = "GI Render scale ratio";
        ui_type = "slider";
        ui_min = 1; ui_max = 10;
        ui_step = 1;
    > = 3;
    
#if !DX9_MODE
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
#else
    #define iRTMaxRays 1
#endif

    uniform float fGIAvoidThin <
        ui_type = "slider";
        ui_category = "GI/AO: 1st Pass (New rays)";
        ui_label = "Avoid thin objects: max thickness";
        ui_tooltip = "Reduce detection of grass or fences";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.750;


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
        ui_min = 0.0; ui_max = 16.0;
        ui_step = 0.01;
    > = 16;

        
#if !DX9_MODE    
    uniform int iMemRadius <
        ui_type = "slider";
        ui_category = "GI/AO: 2nd Pass (Resample)";
        ui_label = "Memory radius";
        ui_min = 0; ui_max = 4;
        ui_step = 1;
    > = 1;
#else
    #define iMemRadius 0
#endif

    // Denoising
    
    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "Spatial: Radius";
        ui_min = 0; ui_max = 4;
        ui_step = 1;
        ui_tooltip = "Define the max distance of smoothing.\n";
    > = 2;
    
    uniform int iGIFrameAccu <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "GI Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
#if DX9_MODE
    > = 16;
#else
    > = 10;
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
    > = 12;
    
    uniform float fAntiGhosting <
        ui_type = "slider";
        ui_category = "GI/AO: 3rd pass (Denoising)";
        ui_label = "Anti-ghosting";
        ui_min = 0; ui_max = 1;
        ui_step = 0.1;
    > = 0.5;
    
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
    > = 0;
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
    > = 0.4;
    
    uniform float fSaturationBoost <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Saturation boost";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.0;
    
    uniform float fGIDarkAmplify <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "Dark color compensation";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Brighten dark colors, useful in dark corners";
    > = 0.0;
    
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
    > = 0.1;
    
    uniform float fGIDarkMerging <
        ui_type = "slider";
        ui_category = "GI: 4th Pass (Merging)";
        ui_label = "In Dark intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much dark areas are affected by GI.";
    > = 0.50;
    
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
        ui_min = 0; ui_max = 512;
        ui_step = 1;
    > = 160;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO: 4th Pass (Merging)";
        ui_label = "Power";
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
    > = 0.75;  
    
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
    > = 0.1;
    


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
    > = 8;
#endif
    
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
    > = 0.75;

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
        ui_category = "Final Merging";
        ui_label = "Distance fading";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Distance from where the effect is less applied.";
    > = 0.9;
    
    
    uniform float fBaseColor <
        ui_type = "slider";
        ui_category = "Final Merging";
        ui_label = "Base color";
        ui_min = 0.0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Simple multiplier for the base image.";
    > = 1.0;
    
    uniform bool bBaseAlternative <
        ui_category = "Final Merging";
        ui_label = "Base color alternative method";
    > = false;

    uniform int iBlackLevel <
        ui_type = "slider";
        ui_category = "Final Merging";
        ui_label = "Black level ";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 0;
    
    uniform int iWhiteLevel <
        ui_type = "slider";
        ui_category = "Final Merging";
        ui_label = "White level";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 255;
    
// Debug light
#if !DX9_MODE
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
#endif

    
// FUCNTIONS

    float IGN(int2 pixel) {
        int frame = framecount % 64; // need to periodically reset frame to avoid numerical issues
        float2 xy = float2(pixel) + 5.588238f * float(frame);
        return frac(52.9829189f * frac(0.06711056f*xy.x + 0.00583715f*xy.y));
    }
    
    float2 IGN2(int2 pixel) {
        return float2(IGN(pixel),IGN(int2(pixel.y,pixel.x)));
    }
    
    int PBN_XMix(int x, int y) {
        return ((x * 212281 + y * 384817) & 0x5555555) * 0.003257328990228013;
    }
    int PBN_YMix(int x, int y) {
        return ((x * 484829 + y * 112279) & 0x5555555) * 0.002004008016032064;
    }
    
    /** Pseudo Blue Noise, adapted from https://observablehq.com/@fil/pseudoblue **/
    float PBN(int2 pixel) {
		// https://observablehq.com/@fil/pseudoblue
		// Inspired by Job van der Zwans research https://observablehq.com/@jobleonard/pseudo-blue-noise
		// and NuSans shader https://www.shadertoy.com/view/7lV3Ry
		// shadertoy implementation: https://www.shadertoy.com/view/mtlSzn
		// The x and y axes are separated for better randomness
		// 1 / 307 == 0.003257328990228013
		// 1 / 499 == 0.002004008016032064 
		
		pixel.x += PBN_XMix(framecount,random);
		
		int iterations = 6;
		uint a,b,v = 0;
		for(int i=0;i<iterations;i+=1) {
			b = pixel.y;
			int2 pixelShift;
			pixelShift.x = pixel.x>>1;
			pixelShift.y = pixel.y>>1;
			a = 1 & (pixel.x ^ PBN_XMix(pixelShift.x, pixelShift.y));
			pixel = pixelShift;
			b = 1 & (b ^ PBN_YMix(pixel.x, pixel.y));
			v = (v << 2) | (a + (b << 1) + 1) % 4;
		}
		return float(v) / (1 << (iterations << 1));
    }

	float2 HaltonSequence(uint index) {

	    float x = 0.0;
	    float base = 0.5;
	    uint i = index;
	    while (i > 0u) {
	        x += (i & 1u) * base;
	        base *= 0.5;
	        i >>= 1u;
	    }
	    
	    float y = 0.0;
	    base = 1.0 / 3.0;
	    i = index;
	    while (i > 0u) {
	        y += (i % 3u) * base;
	        base /= 3.0;
	        i /= 3u;
	    }
	    
	    return float2(x, y);
	}
    
    int getPixelIndexFixed(float2 coords,int2 size) {
        int2 pxCoords = coords*size;
        return pxCoords.x+pxCoords.y*size.x;
    }

    bool isScaledProcessed(float2 coords) {
        return coords.x>=0 && coords.y>0 && coords.x<=1.0/iGIRenderScale && coords.y<=1.0/iGIRenderScale;
    }
    

    
    float2 upCoords(float2 coords,float renderScale) {
    	if(renderScale==1.0) {
    		return coords;
    	}

		int sc = (1.0/renderScale);
		
		int2 upCoordsInt = (coords/renderScale)*BUFFER_SIZE;
		int2 quadZero = int2(upCoordsInt/sc)*sc;
		int currentIndex = IGN(16)*sc*sc;
		int2 offset = int2(currentIndex%sc,currentIndex/sc);
		
		float2 result = float2(quadZero+offset)*ReShade::PixelSize;
		return result;
    		
    }
    
    float2 upCoords(float2 coords) {
    	return upCoords(coords,1.0/iGIRenderScale);
    }
    
    float2 upCoordsSSR(float2 coords) {
    	return upCoords(coords,fSSRRenderScale);
    }
    
    bool isCurrentFrameCoords(float2 coords) {
    	if(iGIRenderScale<=1.1) {
    		return true;
    	}
    	
		int sc = iGIRenderScale;
		
		int2 coordsInt = coords*BUFFER_SIZE;
		int2 quadZero = (coordsInt/sc)*sc;
		int currentIndex = IGN(16)*sc*sc;
		int2 diff = coordsInt-quadZero;
		int pxIndex = diff.x+diff.y*sc;
		
		if(pxIndex==currentIndex) return true;
		return false;
    }

#if!DX9_MODE
    float safePow(float value, float power) {
        return pow(abs(value),power);
    }
    
    float3 safePow(float3 value, float power) {
        return pow(abs(value),power);
    }
#endif
    
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
    
    float maxOf3(float3 a) {
        return max(max(a.x,a.y),a.z);
    }
    
    float minOf3(float3 a) {
        return min(min(a.x,a.y),a.z);
    }
    
    float avgOf3(float3 a) {
        return (a.x+a.y+a.z)/3.0;
    }
    
    float getPureness(float3 rgb) {
        return maxOf3(rgb)-minOf3(rgb);
    }
    
    float getBrightness(float3 rgb) {
        return maxOf3(rgb);
    }

    float3 RGBtoOKL(float3 rgb) {

        // Step 1: Linearize RGB
        float3 r = rgb <= 0.04045 ? rgb / 12.92 : safePow((rgb + 0.055) / 1.055, 2.4);

        // Step 2: Linear RGB to LMS
        r = mul(float3x3(
            0.4122214708, 0.5363325363, 0.0514459929,
            0.2119034982, 0.6806995451, 0.1073969566,
            0.0883024619, 0.2817188376, 0.6299787005
        ), r);

        // Step 3: Non-linear transformation (cube root)
        r = safePow(r, 1.0 / 3.0);

        // Step 4: LMS to OKLab
        r = mul(float3x3(
            0.2104542553, 0.7936177850, -0.0040720468,
            1.9779984951, -2.4285922050, 0.4505937099,
            0.0259040371, 0.7827717662, -0.8086757660
        ), r);

        return r;
    }

    float3 OKLtoRGB(float3 oklab) {
        // Step 1: OKLab to LMS
        float3 r = mul(float3x3(
            1.0, 0.3963377774, 0.2158037573,
            1.0, -0.1055613458, -0.0638541728,
            1.0, -0.0894841775, -1.2914855480
        ), oklab);

        // Step 2: Reverse Non-linear transformation (cube)
        r = r * r * r;

        // Step 3: LMS to linear RGB
        r = mul(float3x3(
            4.0767416621, -3.3077115913, 0.2309699292,
            -1.2684380046, 2.6097574011, -0.3413193965,
            -0.0041960863, -0.7034186147, 1.7076147010
        ), r);

        // Step 4: De-linearize RGB
        r = r <= 0.0031308 ? r * 12.92 : 1.055 * safePow(r, 1.0 / 2.4) - 0.055;

        return r;
    }

// Screen

    float getSkyDepth() {
        float sd = fSkyDepth;
        return sd;
    }

    float isSky(float depth) {
        return bSkyAt0 ? depth==0 : depth>getSkyDepth();
    }
    
	float GetLinearizedDepth(float2 texcoord)
	{
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
		texcoord.y = 1.0 - texcoord.y;
#endif
		texcoord.x /= RESHADE_DEPTH_INPUT_X_SCALE;
		texcoord.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
#if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
		texcoord.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
#else // Do not check RESHADE_DEPTH_INPUT_X_OFFSET, since it may be a decimal number, which the preprocessor cannot handle
		texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
#endif
#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
		texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
#else
		texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
#endif
		float depth = tex2Dlod(ReShade::DepthBuffer, float4(texcoord, 0, 0)).x;

		if(iDepthMode>0) {
			depth = saturate(1.0-pow(1.0-depth,iDepthMode==2?0.03:1.4));
		}
		depth *= RESHADE_DEPTH_MULTIPLIER;
		

#if RESHADE_DEPTH_INPUT_IS_REVERSED
		depth = 1.0 - depth;
#endif
		const float N = 1.0;
		depth /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - depth * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - N);

		return depth;
	}
    
    float2 getDepth(float2 coords) {
        float2 d = iDepthMode>0 ? GetLinearizedDepth(coords) : ReShade::GetLinearizedDepth(coords);
        
        d.y = d.x<fWeaponDepth ? 1 : 0;
        
        if(d.x<fWeaponDepth) {
            d.x = d.x/(fWeaponDepthCorrection*0.01);
        }
        
        
        return d;
    }

    
    float getNormalRoughness() {
    	return fNormalRoughness*(iDepthMode==2?4.0:1.0);
    }
    
    
    float4 getRTF(float2 coords) {
        return getColorSampler(RTFSampler,coords);
    }
    
    float4 getDRTF(float2 coords, float depth, bool ignoreRoughness) {
        float4 drtf = depth;
        drtf.yzw = getRTF(coords).xyz;
        if(!ignoreRoughness && fNormalRoughness>0 && !isSky(drtf.x)) {
            drtf.x += 0.01*drtf.y*getNormalRoughness()*0.05;
        }
        drtf.z = (0.01+drtf.z)*lerp(32,128,drtf.x);
        
        return drtf;
    }
    
    float4 getDRTF(float2 coords, bool ignoreRoughness) {
        return getDRTF(coords,getDepth(coords).x,ignoreRoughness);
    }
    
    float3 getNormal(float2 coords) {
        float3 normal = -(getColorSamplerLod(normalSampler,coords,bSmoothNormals?1.5:0).xyz-0.5)*2;
        return normal;
    }
    
    bool inScreen(float3 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0
            && coords.z>=0.0 && coords.z<=1.0;
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
    
    float3 getWorldPositionForNormal(float2 coords,float roughnessStrength) {
        float depth = getDepth(coords).x;
        
        if(roughnessStrength>0 && fNormalRoughness>0 && !isSky(depth)) {
            float roughness = getRTF(coords).x*roughnessStrength;
            if(bSmoothNormals) roughness *= 1.5;
            depth += 0.25*lerp(1.0,0.0,depth*depth)*roughness*getNormalRoughness()*0.05;
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


    
    float2 nextRand(float2 rand) {
        return  frac(abs(rand+PI)*PI);
    }
    float3 nextRand(float3 rand) {
        return frac(abs(rand+PI)*PI);
    }

    int getPixelIndex(float2 coords,int2 size) {
        int2 pxCoords = coords*size;
        return pxCoords.x*180+pxCoords.y*SQRT2*size.x+framecount;
    }
    
#if !TEX_NOISE
    float randomValue(inout uint seed) {
        seed = seed * 747796405 + 2891336453;
        uint result = ((seed>>((seed>>28)+4))^seed)*277803737;
        result = (result>>22)^result;
        return frac(result/4294967295.0);
    }
#endif

    float2 randomCouple(float2 coords) {
#if TEX_NOISE
/*
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        return abs((getColorSampler(blueNoiseSampler,noiseCoords).rg-0.5)*2.0);
        */
        return getColorSampler(blueNoiseSampler,coords).rg;
#else
        uint seed = getPixelIndex(coords,BUFFER_SIZE);

        float2 v = 0;
        v.x = randomValue(seed);
        v.y = randomValue(seed);
        return v;
#endif
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
#if TEX_NOISE
/*
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        return getColorSampler(blueNoiseSampler,noiseCoords).rgb;
        */
        return getColorSampler(blueNoiseSampler,coords).rgb;
#else
        uint seed = getPixelIndex(coords,BUFFER_SIZE);
        return randomTriple(coords,seed);
#endif
    }
    
    float4 getRayColor(float2 coords) {
        return getColorSampler(rayColorSampler,coords);
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
        
        float2 orientation = normalize(randomCouple(coords)-0.5);
        
        bool validPos = true;
        bool validNeg = true;
        sky = 1.0;
        
        [loop]
        for(int d=1;d<=iThicknessRadius;d++) {
            float2 step = orientation*ReShade::PixelSize*d;
            
            if(validPos) {
                currentCoords = coords+step;
                depth = getDepth(currentCoords).x;
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
                depth = getDepth(currentCoords).x;
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
    
    void PS_MotionMask  (float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outMask : SV_Target0) {
        float2 previousCoords = getPreviousCoords(coords);

        float2 depth = getDepth(coords);
        float2 previousDepth = getColorSampler(previousDepthSampler,previousCoords).xy;

        float mask = depth.x>previousDepth.x+0.018 ? 1 : 0;
		if(mask<1) {
        	float previousM = getColorSampler(resultSampler,coords).a; 
        	mask = max(mask,saturate(1.0-previousM));
        }
	        
        outMask = float4(mask,0,0,1);
    }
    
    
    
    void PS_RTFS(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRTFS : SV_Target0) {
        float depth = getDepth(coords).x;
        
        float2 previousCoords = getPreviousCoords(coords);
        float4 previousRTFS = getColorSampler(previousRTFSampler,previousCoords);
        
        float4 RTFS;
        
    	float2 rand = randomCouple(coords);
    	RTFS.x = roughnessPass(coords,depth);
        
        RTFS.y = thicknessPass(coords,depth,RTFS.a);
        
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
        
        float2 size = BUFFER_SIZE;
        float stepSize = BUFFER_WIDTH/16.0;
        float2 numSteps = size/(stepSize+1);
        
        float avgBrightness = 0;
        int count = 0;
            
        float2 rand = randomCouple(coords);
        [loop]
        for(int it=0;it<=4 && stepSize>=1;it++) {
            float2 stepDim = stepSize/BUFFER_SIZE;
            [loop]
            for(currentCoords.x=bestCoords.x-stepDim.x*(numSteps.x/2);currentCoords.x<=bestCoords.x+stepDim.x*(numSteps.x/2);currentCoords.x+=stepDim.x) {
                [loop]            
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
    
    float4 computeNormal(float2 coords,float3 offset,float roughnessStrength,bool reverse) {
        float3 posCenter = getWorldPositionForNormal(coords,roughnessStrength);
        float3 posNorth  = getWorldPositionForNormal(coords - (reverse?-1:1)*offset.zy,roughnessStrength);
        float3 posEast   = getWorldPositionForNormal(coords + (reverse?-1:1)*offset.xz,roughnessStrength);
        
        float4 r = computeNormal(posCenter,posNorth,posEast);
        float mD = max(abs(posCenter.z-posNorth.z),abs(posCenter.z-posEast.z));
        if(mD>16) r.a = 0;
        return r;
    }


    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
    

		if(bGrassNormalFix) {
	    	float4 DRTF = getDRTF(coords,false);
	    	bool ignoreOrientation = DRTF.z<=DRTF.x*100*fGIAvoidThin;
	    	if(ignoreOrientation) {
				outNormal = float4(float3(0,1,0)*0.5+0.5,1);
				return;
			}
		}
        
        float3 offset = float3(ReShade::PixelSize, 0.0);
        
        float4 normal = computeNormal(coords,offset,1,false);
        float borderTemporal = 0.75;
        if(normal.a==0) {
            normal = computeNormal(coords,offset,1,true);
            borderTemporal = 0.5;
        }
        
        if(bSmoothNormals) {
            float3 offset2 = offset * 7.5*(1.0-getDepth(coords).x);
            float4 normalTop = computeNormal(coords-offset2.zy,offset,0,false);
            float4 normalBottom = computeNormal(coords+offset2.zy,offset,0,false);
            float4 normalLeft = computeNormal(coords-offset2.xz,offset,0,false);
            float4 normalRight = computeNormal(coords+offset2.xz,offset,0,false);
            
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
        
        outNormal = float4(normal.xyz/2.0+0.5,borderTemporal);
        
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
        
        float depth = getDepth(coords).x;
        if(isSky(depth)) {
            outColor = float4(refColor*fSkyColor,1);
            return;
        }
        
		if(fGIBounce>0.0) {
            float3 previousColor = getColorSampler(resultSampler,previousCoords).rgb;
            
			float3 diff = saturate(previousColor-refColor);
			refColor += diff*fGIBounce*3.0;
			refColor = saturate(refColor);
        }
        
        float3 refHSV = RGBtoHSV(refColor);
        
        if(refHSV.y<0.5 && refHSV.z>0.5) {
	        int lod = 1;
	        float3 tempHSV = refHSV;
	        while(lod<=5) {
	        	float3 tempHSV = RGBtoHSV(getColorSamplerLod(resultSampler,previousCoords,lod).rgb);
	        	if(tempHSV.z>refHSV.z*0.5 && tempHSV.y>refHSV.y) {
					refHSV.xy = tempHSV.xy;
				}
	            
	            lod ++;
	        }
	        refColor = HSVtoRGB(refHSV);
        }
        
        if(bRemoveAmbient) {  
            refColor = filterAmbiantLight(refColor);
            refHSV = RGBtoHSV(refColor);
        }
        
        if(fSaturationBoost>0 && refHSV.z*refHSV.y>0.1) {
            refHSV.y = lerp(refHSV.y,saturate(refHSV.y+fSaturationBoost),refHSV.y);
            refColor = HSVtoRGB(refHSV);
        }
        
        
        float3 result = rampColor(refColor);
        if(fGIDarkAmplify>0) {
            float3 okl = RGBtoOKL(result);
            float avgB = getAverageBrightness();
            okl.x = saturate(okl.x+fGIDarkAmplify*(1.0-okl.x));
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
	uniform int sphereRadius = 2;
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
        float2 v = normalize(coords - 0.5)/sphereRadius;
        [loop]
        for(int i=1;i<=sphereRadius;i++) {
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
    
#define HIT_FALSE 0
#define HIT_FRONT 1
#define HIT_BEHIND -1

    int hit(in out float3 currentWp, float3 screenWp, float4 drtf,float3 previousScreenWp, float3 behindWp,in out int stepBehind, in out bool behind,float3 incrementVector,bool ssr, int step) {
    	
		if(fGIAvoidThin>0 && drtf.z<lerp(30,100,drtf.x)*fGIAvoidThin) {
			behind = false;
			return HIT_FALSE;
		}
		
		
		float thickness = drtf.z*(ssr?1.0:drtf.x);
		
		if(!ssr && behind && currentWp.z<=screenWp.z+thickness) {
			return stepBehind>1 ? HIT_BEHIND : HIT_FRONT;
		}
		if(ssr) {
			if(currentWp.z>=screenWp.z && currentWp.z<=screenWp.z+lerp(6.0,32.0,safePow(drtf.x,7.0))) {
				return HIT_FRONT;
			}
		}
		return HIT_FALSE;
    }

#if !DX9_MODE
    float3 getDebugLightWp() {
        return getWorldPosition(fDebugLightPosition.xy,bDebugLightZAtDepth ? getDepth(fDebugLightPosition.xy).x*0.99 : fDebugLightPosition.z);
    }
#endif

    float3 distanceAttenuation(in float3 light, in float dist, in float lightDepth) {
        // RGB: float3 result = smoothstep(1,0,saturate(5.0*dist*fGIDistanceAttenuation/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE))*light;

    	float3 okl = RGBtoOKL(light);
    	okl.x = min(okl.x,smoothstep(1,0,saturate(dist*0.005*fGIDistanceAttenuation)));
    	return OKLtoRGB(okl);
    }
    
    RTOUT traceGI(inout float2 rand, float2 refDepth, float3 refWp,float3 incrementVector) {
    
        RTOUT result;
        result.status = RT_MISSED;
        
        float3 currentWp = refWp;
        float3 previousScreenWp = refWp;
	    bool behind;
	    float3 screenWp;
	    float3 screenCoords;
	    int stepBehind = 0;
	    

        incrementVector = normalize(incrementVector)*max(0.001,refDepth.x);
                
        currentWp += incrementVector;
        screenCoords = getScreenPosition(currentWp);
        result.drtf = getDRTF(screenCoords.xy,true);
        screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
        behind = currentWp.z>screenWp.z;
        
        if(hit(currentWp, screenWp, result.drtf,previousScreenWp,0,stepBehind,behind,incrementVector,false,1)) {
            result.wp = screenWp;
            result.dist = distance(refWp,screenWp);
			result.status = RT_HIT_BEHIND;
            return result;
        }
        
        
        float3 refVector = normalize(incrementVector);
        incrementVector = refVector;
        
        behind = false;
        float3 behindWp = 0;
 
        int step = -1;
        incrementVector *= 0.1;
        
        float maxDist = sqrt(BUFFER_WIDTH*BUFFER_WIDTH+BUFFER_HEIGHT*BUFFER_HEIGHT)*0.5;
        
        result.dist = 0;

        
        while(result.dist<maxDist && step<BUFFER_WIDTH*0.025) {
            step++;

            currentWp += incrementVector;
            result.dist = distance(currentWp.xyz,refWp.xyz);
            screenCoords = getScreenPosition(currentWp);
            if(!inScreen(screenCoords.xy)) break;
            
            float2 currentDepth = getDepth(screenCoords.xy);
            result.drtf = getDRTF(screenCoords.xy,currentDepth.x,true);
            screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
            bool previousBehind = behind;
            behind = currentWp.z>screenWp.z;
            if(behind) {
                stepBehind++;
                if(stepBehind==1) {
                    behindWp = currentWp;
                }
            }
            
            if(isSky(result.drtf.x)) {
                result.status = RT_HIT_SKY;
                result.wp = currentWp;
            }
            
            if(!inScreen(screenCoords)) break;
            
            int isHit = hit(currentWp, screenWp, result.drtf,previousScreenWp,behindWp,stepBehind,behind,incrementVector,false,step);
            
            if(isHit) {
                result.status = isHit==HIT_BEHIND ? RT_HIT_BEHIND :  RT_HIT;
				if(isHit==HIT_FRONT) {
                	float3 hitNormal = getNormal(screenCoords.xy);
                	float d = dot(refVector,hitNormal);
                	if(d>0) result.status = RT_HIT_BEHIND;
                }

                result.wp = result.status==RT_HIT_BEHIND ? behindWp : currentWp;
                return result;
            }
            
            rand = nextRand(rand);
            float nextStepLength = round(lerp(1,16,saturate(rand.x*0.1+step/128.0)));
	            float2 nextWp = float2(
	                refVector.x>0 ? floor(currentWp.x+nextStepLength) : ceil(currentWp.x-nextStepLength),
	                refVector.y>0 ? floor(currentWp.y+nextStepLength) : ceil(currentWp.y-nextStepLength)
	            );
            
            float2 dist = abs(nextWp.xy-currentWp.xy);
            float minDist = min(dist.x, dist.y);
			minDist *= 1.0+step*0.05;
            incrementVector = refVector*minDist;
            
            if(!behind) {
                stepBehind = 0;
            }

            previousScreenWp = screenWp;
	            
        }
        
        return result;
    }
    
    RTOUT traceGItarget(inout float2 rand, float2 refDepth, float3 refWp,float3 incrementVector,float3 targetWp) {
    
        RTOUT result;
        result.status = RT_MISSED;
        
        float3 currentWp = refWp;
        float3 previousScreenWp = refWp;

	    float3 screenWp;
	    float3 screenCoords;

        incrementVector = normalize(incrementVector)*max(0.001,refDepth.x);
                
        currentWp += incrementVector;
        screenCoords = getScreenPosition(currentWp);
        result.drtf = getDRTF(screenCoords.xy,true);
        screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
        previousScreenWp = refWp;
                
        bool behind = currentWp.z>screenWp.z;
        int stepBehind = 0;        
        
        float3 refVector = normalize(incrementVector);
        
    	float maxInc = distance(refWp,targetWp)/128.0;
    	if(maxInc<1) refVector *= maxInc;
        
        incrementVector = refVector;
        
        float3 behindWp = 0;
         
        int step = -1;
        //incrementVector *= 0.1;
        
        float maxDist = distance(refWp,targetWp);

        result.dist = 0;
        
        int checkHit = 0;
        
        while(result.dist<=maxDist && step<ceil(32*fRTPrecision)) {
            step++;
            
            result.dist = distance(currentWp,refWp);
            currentWp += incrementVector;
            screenCoords = getScreenPosition(currentWp);
            
            if(!inScreen(screenCoords)) break;
            
            result.drtf = getDRTF(screenCoords.xy,false);
            screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
            bool previousBehind = behind;
            behind = currentWp.z>screenWp.z;
            
            if(behind) {
                stepBehind = max(1,stepBehind+1);
                if(stepBehind==1) {
                    behindWp = currentWp;
                }
            }
            
            int isHit = hit(currentWp, screenWp, result.drtf,previousScreenWp,behindWp,stepBehind,behind,incrementVector,false,step);
   		 bool checkMore = false;
			if(isHit && checkHit==0) {
				result.status = isHit==HIT_BEHIND ? RT_HIT_BEHIND : (maxDist-result.dist<=2 ? RT_HIT_LIGHT : RT_HIT);
				result.wp = result.status==RT_HIT_BEHIND ? behindWp : currentWp;
				
				isHit = false;
				checkMore = true;				
            }
            
            if(isHit) {
            	result.status = isHit==HIT_BEHIND ? RT_HIT_BEHIND : (maxDist-result.dist<=1.0 ? RT_HIT_LIGHT : RT_HIT);
				if(isHit==HIT_FRONT && maxDist-result.dist<=2) {
                	float3 hitNormal = getNormal(screenCoords.xy);
                	float d = dot(refVector,hitNormal);
                	if(d>0) result.status = RT_HIT_BEHIND;
                }
                result.wp = result.status==RT_HIT_BEHIND ? behindWp : currentWp;
                return result;
            }
            
            if(checkHit>0 && distance(refWp,result.wp)<result.dist) {
            	result.dist = distance(refWp,result.wp);
            	if(result.status!=RT_HIT_BEHIND && maxDist-result.dist<=2) {
                	float3 hitNormal = getNormal(screenCoords.xy);
                	float d = dot(refVector,hitNormal);
                	if(d>0) result.status = RT_HIT_BEHIND;
                }
            	return result;         	
            }
            
            
            if(checkHit>=10) {
            	return result;
	        } else if(checkHit>0) {
            	checkHit++;
            	
	            if(!behind) {
	                stepBehind = 0;
	            }
	
	            previousScreenWp = screenWp;
            	
            } else if(checkMore) {
            	checkHit = 1;
            	
           	 currentWp -= incrementVector;
        		incrementVector = incrementVector*0.1;
            	if(behind) stepBehind--;
           	 behind = previousBehind;
            	
            } else {
            
	            rand = nextRand(rand);
	            float nextStepLength = round(lerp(1,16,saturate(rand.x*0.1+step/128.0)));
	            float2 nextWp = float2(
	                refVector.x>0 ? floor(currentWp.x+nextStepLength) : ceil(currentWp.x-nextStepLength),
	                refVector.y>0 ? floor(currentWp.y+nextStepLength) : ceil(currentWp.y-nextStepLength)
	            );
	            
	            float2 dist = abs(nextWp.xy-currentWp.xy);
	            float minDist = min(dist.x, dist.y);
	            incrementVector = refVector*minDist;
	                
	          
	            if(!behind) {
	                stepBehind = min(stepBehind-1,0);
	            }
	
	            previousScreenWp = screenWp;
            }
        }

		bool isHitBehind = (stepBehind>1 || (currentWp.z>=screenWp.z+50 && result.drtf.z>=50));
        result.status = isHitBehind ? RT_HIT_BEHIND : RT_HIT_LIGHT;
        result.wp = targetWp;
        result.dist = distance(refWp,targetWp);
        
        return result;
    }

// GI

    float weightLight(float3 color) {
#if !DX9_MODE
        float3 hsv = RGBtoHSV(color);
        return (1+hsv.y)*hsv.z*0.5;
#else
        return maxOf3(color);
#endif
    }
    


    	
    void handleHit(
    	in float3 refWp, in float3 refNormal,
        in bool doTargetLight, in float4 targetColor, in RTOUT hitPosition,float3 targetWp,
        inout float3 sky, inout float4 bestRay, inout float sumAO, inout float hits, inout float3 mergedGiColor,
        in bool ignoreAO
    ) {

        if(hitPosition.status <= RT_MISSED) {
    		if(!ignoreAO) {
	            hits += 1.0;
	            sumAO+=1;
            }
            return;
        }
        
        float3 screenCoords = getScreenPosition(hitPosition.wp);
        
        if(!inScreen(screenCoords.xy)) {
    		if(!ignoreAO) {
	            hits += 1.0;
	            sumAO+=1;
            }
            return;
        }
        
        
        if(hitPosition.status==RT_HIT_SKY || isSky(screenCoords.z)) {
            float4 giColor = doTargetLight ? targetColor : getRayColor(screenCoords.xy);
            float b = getBrightness(giColor.rgb);
            if(b>bestRay.a) {
                bestRay = float4(screenCoords,b);
            }

        	float orientation = dot(refNormal,normalize(hitPosition.wp-refWp));
        	giColor.rgb *= saturate(0.15+orientation);
            
            sky = max(sky,giColor.rgb);
            
            if(!ignoreAO) {
	            hits += 1.0;
	            sumAO+=1;
            }
            
            return;
        }
        
        
        float4 DRTF = getDRTF(screenCoords.xy,false);  
        bool ignoreOrientation = DRTF.z<=DRTF.x*100*fGIAvoidThin;
        if(!ignoreOrientation && !ignoreAO) {
            float ao = doTargetLight 
                    ? 1.0-maxOf3(targetColor.rgb)
                    : 4.0*hitPosition.dist/iAODistance;
                    
            sumAO += saturate(ao);
            hits += 1.0;
        }
        
        if(hitPosition.status==RT_HIT_BEHIND) {
        	if(!doTargetLight) {
				float4 giColor = getRayColor(screenCoords.xy);  
	            float hitB = weightLight(giColor.rgb);
	            if(hitB>bestRay.a) {
	                bestRay = float4(screenCoords,hitB);
	            }
            }
            
            return;
        }
        
        
        float4 giColor;
        if(doTargetLight && hitPosition.status==RT_HIT_LIGHT) {
        	giColor = targetColor;
        	
        	if(!ignoreOrientation) {
	        	float3 lightRay = normalize(hitPosition.wp-refWp);
	        	float or = dot(refNormal,lightRay);
	        	giColor.rgb *= saturate(0.5+or*0.5);
        	}
        	
        } else if(!doTargetLight && !(bDebugLight && bDebugLightOnly)) {
            giColor = getRayColor(screenCoords.xy);
        } else {
        	return;
        }

        float b = weightLight(giColor.rgb);
        if(b>bestRay.a && !doTargetLight) {
            bestRay = float4(screenCoords,b);
        }
        
        giColor.rgb = distanceAttenuation(giColor.rgb,hitPosition.dist,screenCoords.z);
	    mergedGiColor.rgb = max(mergedGiColor.rgb,giColor.rgb);        
    }
    
    void handleHit(
    	in float3 refWp, in float3 refNormal,
        in bool doTargetLight, in float4 targetColor, in RTOUT hitPosition,float3 targetWp,
        inout float3 sky, inout float4 bestRay, inout float sumAO, inout float hits, inout float3 mergedGiColor
    ) {
    	handleHit(
    		refWp, refNormal,
        	doTargetLight, targetColor, hitPosition, targetWp,
        	sky, bestRay, sumAO, hits, mergedGiColor,
        	false
        );
    }

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outBestRay : SV_Target1) {
        
        if(!isScaledProcessed(coords)) {
            outGI = float4(0,0,0,1);
            outBestRay = float4(0,0,0,1);
            return;
        }
        
        float2 originalCoords = coords;
        
        coords = upCoords(coords);
        
        float2 depth = getDepth(coords);
        if(isSky(depth.x)) {
            outGI = float4(0,0,0,1);
            outBestRay = float4(coords,depth.x,fSkyColor);
            return;
        }
        
        
        float3 refWp = getWorldPosition(coords,depth.x);
        float3 refNormal = getNormal(coords);
        
        float4 bestRay = 0;

        float3 sky = 0.0;
        float3 mergedGiColor = 0;     
        
        float sumAO = 0;
        float hits = 0;
        
#if TEX_NOISE
        float3 rand = randomTriple(coords+0.05*framecount);
#else
        uint seed = getPixelIndex(coords,BUFFER_SIZE);
        float3 rand = randomTriple(coords,seed);
#endif

        
        int rays = 0;
        
#if !DX9_MODE
        if(bDebugLight) {
        	rays += 1; 
            float3 targetWp = getDebugLightWp() + (rand-0.5)*iDebugLightSize*0.9;
            float3 lightVector = normalize(targetWp-refWp);
            float4 targetColor = float4(fDebugLightColor,0.5);

            RTOUT hitPosition = traceGItarget(rand.xy,depth,refWp,lightVector,targetWp);
            if(hitPosition.status>RT_MISSED) {
                handleHit(
                	refWp,refNormal,
                    true, targetColor,hitPosition,targetWp,
                    sky, bestRay, sumAO, hits, mergedGiColor
                );
            }
            
            if(bDebugLightOnly) {
                outBestRay = bestRay;
                outGI = float4(max(mergedGiColor,sky),hits>0 ? saturate(sumAO/hits) : 1.0);
                return;
            }
        }
#endif

		float4 DRTF = getDRTF(coords,true);
		bool ignoreOrientation = DRTF.z<=DRTF.x*100*fGIAvoidThin;
		
		

        
#if !DX9_MODE
        
        int maxRand = iRTMaxRays*3;
        [loop]
        while(rays<iRTMaxRays) {
#endif
			rays += 1;
            rand = randomTriple(coords,seed);

            float3 lightVector = ignoreOrientation 
				? normalize((rand-0.5)*2)
				: normalize(refNormal+normalize((rand-0.5)*2));
            
            RTOUT hitPosition = traceGI(rand.xy,depth,refWp,lightVector);
            
            handleHit(
                refWp,refNormal,
                false, 0,hitPosition, 0,
                sky, bestRay, sumAO, hits, mergedGiColor
            );
#if !DX9_MODE
        }
#endif

        outBestRay = bestRay;
        outGI = float4(max(mergedGiColor,sky),hits>0 ? saturate(sumAO/hits) : 1.0);
    }
    
    
    float getBorderProximity(float2 coords) {
        float2 borderDists = min(coords,1.0-coords)*BUFFER_SIZE;
        float borderDist = min(borderDists.x,borderDists.y);
        return borderDist<=iHudBorderProtectionRadius ? float(iHudBorderProtectionRadius-borderDist)/iHudBorderProtectionRadius : 0;
    }
    
    
    float getLightWeight(float2 coords, float4 ray, int2 coordsInt) {
		int comp = (coordsInt.x+coordsInt.y+framecount%3)%3;
    	if(comp==0) return abs(ray.x-0.2)*ray.a;
    	else if(comp==1) return (1.0-abs(ray.x-0.5))*ray.a;
    	else return abs(ray.x-0.8)*ray.a;
    }
    
    void PS_GIFill(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outBestRay : SV_Target) {
    
        if(!isScaledProcessed(coords)) {
            outBestRay = float4(0,0,0,1);
            return;            
        }
        
		int2 coordsInt = coords*BUFFER_SIZE;

        float2 pixelSize = ReShade::PixelSize;
        float4 bestRay = getColorSampler(bestRaySampler,coords);
        bestRay.a = getLightWeight(coords,bestRay,coordsInt);
        
#if TEX_NOISE
        float3 rand = randomTriple(coords+0.05*framecount);
#else
        uint seed = getPixelIndex(coords,BUFFER_SIZE);
        float3 rand = randomTriple(coords,seed);
#endif
        int2 delta;         
        int2 res = floor(BUFFER_SIZE/RESV_SCALE);
        int maxDist = 4;
        
        [loop]
        for(delta.x=-maxDist;delta.x<=maxDist;delta.x+=1) {
        	[loop]
            for(delta.y=-maxDist;delta.y<=maxDist;delta.y+=1) {
                float d = length(delta);
                if(d>maxDist) continue;
                
                float2 currentCoords = coords + delta*pixelSize;
                rand = nextRand(rand);
                currentCoords += (rand.xy-0.5)*0.1*d/iGIRenderScale;
                if(!isScaledProcessed(currentCoords)) continue;
                
                float4 ray = getColorSampler(bestRaySampler,currentCoords);
                ray.a = getLightWeight(coords,ray,coordsInt);
        		if(ray.a>=bestRay.a) {
                    bestRay = ray;
                }
            }
        }

        outBestRay = bestRay;
        
    }
    
    float minDistWith(float4 points[16], float3 newPoint,int count) {
    	float minDist = 4096;
    	for(int index=0;index<count;index+=1) {
    		if(points[index].a==0) continue;
            float dist =  distance(newPoint,points[index].xyz);
			minDist = min(dist,minDist);
        }
        return minDist;          
    }
    
    void PS_GILightPass2(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {

        if(!isScaledProcessed(coords)) {
            outGI = float4(0,0,0,1);
            return;            
        }
        float2 originalCoords = coords;
        
        coords = upCoords(coords);

        float2 depth = getDepth(coords);
        if(isSky(depth.x)) {
            outGI = float4(0,0,0,1);
            return;
        }
        

		float4 DRTF = getDRTF(coords,true);
		bool ignoreOrientation = DRTF.z<=DRTF.x*100*fGIAvoidThin;
        		
        float3 refWp = getWorldPosition(coords,depth.x);
        float3 refNormal = getNormal(coords);
        
        float3 mergedGiColor = 0;
        
        float hits = 0;
        float sumAO = 0;
        
        float3 sky = 0.0;
        float4 bestRay;
	    
	    float3 rand;
	        
        if(iMemRadius>0) {
	                                  
	        
	#if TEX_NOISE
	        rand = randomTriple(coords+0.05*framecount);
	#else
	        uint seed = getPixelIndex(coords,BUFFER_SIZE);
	        rand = randomTriple(coords,seed);
	#endif
	        float2 pixelSize = ReShade::PixelSize;
	        
	            
	#if !DX9_MODE
	
	        float2 currentCoords = coords;
	        
	    	float2 currentDelta = coords;
	    	int startIndex = floor(rand.z*1000)%32;
	    	int samples = iMemRadius;
	    	
	    	float4 bestHit[16];
            int hitIndex = 0;
            int2 coordsInt = coords*BUFFER_SIZE;
			int pxIndex = (coordsInt.x+coordsInt.y+framecount%2)%2;
	    				
	
	    	for(uint index=0;hitIndex<samples && index<samples*2;index++) {
	    		
    			if(index==0) {
    				currentCoords = coords;
    			} else if(index==1) {
    				currentCoords = coords;
    				currentCoords.y += (pxIndex==0?-1:1)*ReShade::PixelSize.y*iGIRenderScale;
    			} else if(index==2) {
    				currentCoords = coords;
    				currentCoords.x += (pxIndex==1?-1:1)*ReShade::PixelSize.x*iGIRenderScale;
    			} else {
		    		currentDelta = HaltonSequence(index+startIndex);
		    		
		    		if(index>0) {
		    			currentCoords = coords+(currentDelta-0.5)*2*ReShade::PixelSize*(hitIndex+1)*(hitIndex+1);
		    		}
	    		}
	    		
	    		
	    		
	    		if(!inScreen(currentCoords.xy) || currentCoords.x<0.001 && currentCoords.y<0.001) {
	    			continue;
	    		}
	    		
	            currentCoords = getColorSampler(bestRayFillSampler,currentCoords/iGIRenderScale).xy;
	            
	            
	            if(!inScreen(currentCoords.xy) || currentCoords.x<0.001 && currentCoords.y<0.001) {
	    			continue;
	    		}
	            float3 targetCoords = float3(currentCoords,getDepth(currentCoords).x);
                    
                float3 targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
                targetWp += rand*8*fHudBorderProtectionStrength*getBorderProximity(targetCoords.xy);
                
                float minDist = minDistWith(bestHit,targetWp,hitIndex);
	            if(minDist<16)  {
	    			continue;
	    		}
                
                float4 targetColor = getRayColor(targetCoords.xy);
                if(!isSky(targetCoords.z)) {
                	float dist = distance(refWp,targetWp);
                	float3 expectedColor = distanceAttenuation(targetColor.rgb,dist,targetCoords.z);
                	if(maxOf3(expectedColor-mergedGiColor.rgb)<=10.0/256) {
                		continue;
                	}
				}
                
                float3 lightVector = normalize(targetWp-refWp);
                RTOUT hitPosition = traceGItarget(rand.xy,depth,refWp,lightVector,targetWp);
                if(hitPosition.status!=RT_MISSED_FAST) {
                    handleHit(
						refWp,refNormal,
                        true, targetColor, hitPosition, targetWp,
                        sky, bestRay, sumAO, hits, mergedGiColor
                    );

                    bestHit[hitIndex] = float4(targetWp,maxOf3(targetColor.rgb));
                    hitIndex = min(hitIndex+1,16);
                }
	    		
	    	}
						
			        
	
	#endif
        
        }
        
        float4 firstPassFrame = getColorSampler(giPassSampler,originalCoords);
        
        mergedGiColor.rgb = max(mergedGiColor.rgb,firstPassFrame.rgb);
        mergedGiColor.rgb = max(mergedGiColor.rgb,sky);

        outGI = float4(mergedGiColor.rgb,firstPassFrame.a);
    }

// SSR
    float3 computeSSR(float2 coords,float brightness) {
        float4 ssr = getColorSampler(ssrAccuSampler,coords);

        float roughness = getRTF(coords).x;
        
        float rCoef = lerp(1.0,saturate(1.0-roughness*10),fSSRMergingRoughness);

        float coef = fSSRMerging*2.0*saturate(0.35+brightness)*rCoef;

        if(fSSRMergingOrientation>0) {
            float3 normal = getNormal(coords);
            float3 preferedOrientation = normalize(float3(0,-1,-0.5));
            float oCoef = saturate(dot(normal,preferedOrientation));
            coef *= (1.0-fSSRMergingOrientation)+lerp(1.0,oCoef,fSSRMergingOrientation)*fSSRMergingOrientation;
        }

        return ssr.rgb*coef;
            
    }

    RTOUT traceSSR(inout float3 rand, float3 refWp,float3 incrementVector) {
    
        RTOUT result;
        result.status = RT_MISSED;
        
        float3 currentWp = refWp;
        
        float3 refVector = normalize(incrementVector);

        incrementVector = refVector*0.01;
                
        currentWp += incrementVector;
        float3 screenCoords = getScreenPosition(currentWp);
        
        result.drtf = getDRTF(screenCoords.xy,false);
        
        
        float3 screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
        float3 previousScreenWp = refWp;
        int stepBehind = 0;
        
        bool behind = false;
        bool isHit = hit(currentWp, screenWp, result.drtf,previousScreenWp,0,stepBehind,behind,incrementVector,true,1);
        if(isHit) return result;
        
        
        
        incrementVector = refVector;
        
        float3 behindWp = 9999;
#if !DX9_MODE
        float3 beforeBehind = 0;
        float3 previousWp = refWp;
#endif
 
        int step = -1;
        incrementVector *= 0.1;
        
        float maxDist = sqrt(BUFFER_WIDTH*BUFFER_WIDTH+BUFFER_HEIGHT*BUFFER_HEIGHT);
        int maxSteps = 256;

        result.dist = 0;
        
        int checkHit = 0;
        bool previousBehind = false;
        
        float bestDist = 9999;
        
        float3 bestWp = 9999;
        
        while(step<maxSteps*2 && result.dist<maxDist) {
            step++;
            if(step>maxSteps && checkHit<1) incrementVector *= checkHit>0 ? 1 : 1.05;

            currentWp += incrementVector;
            result.dist = distance(refWp,currentWp);
            screenCoords = getScreenPosition(currentWp);
            
            if(!inScreen(screenCoords.xy)) {
            	if(refVector.z<-0.5) {
            		result.status = RT_MISSED;
            	}
				break;
			}
			
            
            
            result.drtf = getDRTF(screenCoords.xy,false);
            
            screenWp = getWorldPosition(screenCoords.xy,result.drtf.x);
            
            previousBehind = behind;
            behind = currentWp.z>screenWp.z;
            
			if(isSky(result.drtf.x)) {
                result.status = RT_HIT_SKY;
                result.wp = currentWp;
            }
            
            if(!inScreen(screenCoords)) {
            	if(refVector.z<-0.5) {
            		result.status = RT_MISSED;
            	}
				break;
			}
            
            
            if(behind) {
                stepBehind++;
                if(stepBehind==1) {
                    behindWp = currentWp;
#if !DX9_MODE
                    beforeBehind = previousWp;
#endif
                }
            }
            
            isHit = hit(currentWp, screenWp, result.drtf,previousScreenWp,behindWp,stepBehind,behind,incrementVector,true,step);
            bool checkMore = false;	
            if(isHit && checkHit==0) {
				result.status = isHit==HIT_BEHIND ? RT_HIT_BEHIND : RT_HIT;
				if(isHit==HIT_FRONT) {
                	float3 hitNormal = getNormal(screenCoords.xy);
                	float d = dot(refVector,hitNormal);
                	if(d>0) result.status = RT_HIT_BEHIND;
                }
                result.wp = currentWp;
				
				float3 offset = incrementVector*abs(currentWp.z-screenWp.z)/length(incrementVector);
                result.wp -= offset;
                
            	isHit = false;
            	checkMore = true;
            }
        	            
            if(isHit) {
                result.status = isHit==HIT_BEHIND ? RT_HIT_BEHIND : RT_HIT;
				if(isHit==HIT_FRONT) {
                	float3 hitNormal = getNormal(screenCoords.xy);
                	float d = dot(refVector,hitNormal);
                	if(d>0) result.status = RT_HIT_BEHIND;
                }
                result.wp = currentWp;
                
                float3 offset = incrementVector*abs(currentWp.z-screenWp.z)/length(incrementVector);
                result.wp -= offset;
                
                return result;
            }
            
            previousScreenWp = screenWp;
            
            if(checkHit>=10) {
            	return result;
            } else if(checkHit>0) {
            	
            	checkHit++;
            	
	            if(!behind) {
	                stepBehind = 0;
	            }
	
	            previousScreenWp = screenWp;
            	
            } else if(checkMore) {
            	checkHit = 1;
            	
            	if(behind) stepBehind--;
            	
				currentWp -= incrementVector;
				incrementVector = incrementVector*0.1;
				behind = previousBehind;
            	
            } else {
            	
            	if(step<=maxSteps) {
	                rand = nextRand(rand);
	                incrementVector = refVector*(1.0+0.3*rand.x)*lerp(2.5,0.05,screenCoords.z);
	            }
	            
	            if(!behind) {
	                stepBehind = 0;
	            }
            }
            
#if !DX9_MODE
            previousWp = currentWp;
#endif
        }
        
        if(behindWp.x!=9999 && (behindWp.z>RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fSkyDepth*0.75 || distance(currentWp,behindWp)<100)) {
			result.wp = behindWp;
			result.status = RT_HIT;
        }
        if(result.status != RT_MISSED) result.status = RT_HIT;
        return result;
    }

    void PS_SSR(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!bSSR || fSSRMerging==0.0) {
            outColor = 0.0;
            return;
        }
        
        if(coords.x>fSSRRenderScale || coords.y>fSSRRenderScale) {
            outColor = 0;
            return;
        }
        
        
        coords = upCoordsSSR(coords);
            
        float2 depth = getDepth(coords);
        
        if(isSky(depth.x)) {
            outColor = 0;
        } else {
        
            float4 result = 0;
                
            float3 targetWp = getWorldPosition(coords,depth.x); 
            float3 targetNormal = getNormal(coords);
                           
            float3 lightVector = normalize(reflect(targetWp,targetNormal));
            
            float3 rand = randomTriple(coords);
	        if(bSmoothNormals) {
	        	float4 drtf = getDRTF(coords,false).y;
	        	lightVector += 0.2*(rand-0.5)*saturate(drtf.y*3)*getNormalRoughness();
	        	lightVector = normalize(lightVector);
	        }
            
            RTOUT hitPosition =  traceSSR(rand,targetWp,lightVector);
            

            if(hitPosition.status>RT_HIT_BEHIND) {
                float3 screenPosition = getScreenPosition(hitPosition.wp.xyz);
            	float2 previousCoords = getPreviousCoords(screenPosition.xy);
            	if(inScreen(previousCoords)) {
	                float3 hitNormal = getNormal(screenPosition.xy);
	                if(distance(hitNormal,targetNormal)>=0.2) {
	                    result = float4(getColorSampler(resultSampler,previousCoords).rgb,1);
	                }
                }
            } else {
            	result = float4(getColorSamplerLod(ssrPreviousAccuSampler,coords,4.0).rgb,1)*0.9;
            }
            

            outColor = result;
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

    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
		float4 selectedGI;
		float2 previousCoords = getPreviousCoords(coords);
		
		float motionMask = getColorSampler(motionMaskSampler,coords).x;
		if(motionMask>0.95) {
			float lod = lerp(0.0,5.0,(motionMask-0.95)/0.05);
			selectedGI = getColorSamplerLod(giPass2Sampler,coords/iGIRenderScale,lod);
		} else if(isCurrentFrameCoords(coords)) {
			selectedGI = getColorSampler(giPass2Sampler,coords/iGIRenderScale);
			if(bTAAFlicker && inScreen(previousCoords)) {
				float4 refColor = getColorSampler(giSmooth2PassSampler,previousCoords);
				float3 diff = abs(selectedGI.rgb-refColor.rgb);
				if(getBrightness(diff)<0.5) selectedGI = lerp(selectedGI,refColor,0.5);
			}
		} else {
			if(!inScreen(previousCoords)) previousCoords = coords;
			float4 previousColor = getColorSampler(giSmooth2PassSampler,previousCoords);
			selectedGI = previousColor;
		}
		
		outGI = selectedGI;
    }
    
	void smoothWeight(
        float2 refDepth, float motionMask, float3 refNormal,float3 refWp,
        sampler sourceGISampler,float2 currentCoords,
        inout float2 weightSum, inout float4 giAo
    ) {
    	
        float2 depth = getDepth(currentCoords);
        if(isSky(depth.x)) {
#if DX9_MODE
            return;
#else
            depth = getColorSampler(previousDepthSampler,currentCoords).x;
            if(isSky(depth.x)) {
                return;
            }
#endif
        }
        
        if(depth.y != refDepth.y) {
            return;
        }
        
        float2 weight = 1.0;
        		
        float nw;
        // Normal weight
        {
			float3 normal = getNormal(currentCoords);
            nw = saturate(dot(normal,refNormal));

			float normalDist = safePow(nw,max(1,iGIRenderScale*0.25));
            weight.x *= normalDist*safePow(normalDist,6);
			weight.y *= 0.01+normalDist;
        }
        
        // Depth weight
        {
        	float depthDiff = abs(depth.x-refDepth.x);
        	depthDiff *= 1.0-saturate(refDepth.x*10*0.15);
        	weight *= saturate(1.0-0.25*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*depthDiff);
        }

        float4 curGiAo = getColorSampler(sourceGISampler,currentCoords);
        
        //giAo.rgb += curGiAo.rgb*weight.x;
        giAo.a += curGiAo.a*weight.y;
        
        
        if(weight.x>0.001) {
        
        	if(weightSum.x>10) {
        		float diff = abs(weight.x-(weightSum.x-10));
	        	if(diff>0.07) {
	        		weight.x = 0;
	        		weightSum += weight;
					return; 
				}
        	}
        	
        	giAo.rgb += curGiAo.rgb*weight.x;
			weight.x += 10;
        	weightSum += weight;
		} else {
			weight.x = 0;
        	weightSum += weight;
		}
		

    }
    
    void smoothLine(
    	in float2 coords, 
		in float2 refDepth, in float3 refNormal, in float3 refWp, in float motionMask,
		in float2 centerWeight, in float4 centerGiAo,
    	in float2 dir, in float dist,
    	inout float4 result, inout float aoCount, inout float valid
	) {
    	
        coords += ReShade::PixelSize;
        
		float2 weightSum = 0;
		float4 giAo = 0;
		
		float2 currentCoords;

		currentCoords = coords+ReShade::PixelSize.xy*dir*dist;
        if(inScreen(currentCoords)) {
            if(iGIRenderScale>1) currentCoords = upCoords(((currentCoords-ReShade::PixelSize)/(iGIRenderScale*ReShade::PixelSize))*ReShade::PixelSize);
         
            smoothWeight(
                refDepth, motionMask, refNormal,refWp,
                giSmoothPassSampler,currentCoords,
                weightSum, giAo
            );
        }
        
		currentCoords = coords-ReShade::PixelSize.xy*dir*dist;
        if(inScreen(currentCoords)) {
            if(iGIRenderScale>1) currentCoords = upCoords(((currentCoords)/(iGIRenderScale*ReShade::PixelSize))*ReShade::PixelSize);
         
            smoothWeight(
                refDepth, motionMask, refNormal,refWp,
                giSmoothPassSampler,currentCoords,
                weightSum, giAo
            );
        }
        
        if(weightSum.x<20 && dist>=2) {
    		weightSum = 0;
    		giAo = 0;
    		
    		dist *= 0.5;
			currentCoords = coords+ReShade::PixelSize.xy*dir*dist;
	        if(inScreen(currentCoords)) {
	            if(iGIRenderScale>1) currentCoords = upCoords(((currentCoords-ReShade::PixelSize)/(iGIRenderScale*ReShade::PixelSize))*ReShade::PixelSize);
	         
	            smoothWeight(
	                refDepth, motionMask, refNormal,refWp,
	                giSmoothPassSampler,currentCoords,
	                weightSum, giAo
	            );
	        }
	        
			currentCoords = coords-ReShade::PixelSize.xy*dir*dist;
	        if(inScreen(currentCoords)) {
	            if(iGIRenderScale>1) currentCoords = upCoords(((currentCoords)/(iGIRenderScale*ReShade::PixelSize))*ReShade::PixelSize);
	         
	            smoothWeight(
	                refDepth, motionMask, refNormal,refWp,
	                giSmoothPassSampler,currentCoords,
	                weightSum, giAo
	            );
	        }
        }
        
		weightSum += centerWeight;
		giAo += centerGiAo;		
		
		if(weightSum.x>=20) {
			weightSum.x = weightSum.x%10;
			result.rgb += giAo.rgb;
        	valid += weightSum.x;
        }
        
        result.a += giAo.a;
        aoCount += weightSum.y;
    	
    }
    
    void PS_Smooth2Pass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
        
        float2 refDepth = getDepth(coords);
        
        if(isSky(refDepth.x)) {
            outGI = float4(getColor(coords).rgb,1);
            return;
        }

        float3 refNormal = getNormal(coords);  
        float3 refWp = getWorldPosition(coords,refDepth.x);
        
        
    	
        float2 currentCoords;
        
        float motionMask = getColorSampler(motionMaskSampler,coords).x;

		float2 delta;
		
		float2 weightSum;
        float4 giAo = 0.0;
		float2 centerWeight;
		float4 centerGiAo;
        
		float dist = iSmoothRadius*round(IGN(coords*BUFFER_SIZE)*9);
		
		float4 result = 0;
		float2 dir;
		float aoCount = 0;
		float valid = 0;
		
	// Center
        currentCoords = coords;
     
        smoothWeight(
            refDepth, motionMask, refNormal,refWp,
            giSmoothPassSampler,currentCoords,
            weightSum, giAo
        );
        centerWeight = weightSum;
		centerGiAo = giAo;
		
		result.a += centerGiAo.a;
		aoCount += centerWeight.y;
		
	// Hori
		dir = float2(1,0);
		smoothLine(
    		coords, 
			refDepth, refNormal, refWp, motionMask,
			centerWeight, centerGiAo,
    		dir, dist,
    		result, aoCount, valid
    	);
        
	// Vert
		dist = iSmoothRadius*round(IGN(coords*BUFFER_SIZE+1)*9);
	
		dir = float2(0,1);
		smoothLine(
    		coords, 
			refDepth, refNormal, refWp, motionMask,
			centerWeight, centerGiAo,
    		dir, dist,
    		result, aoCount, valid
    	);
        
	// Diag D
		dist = iSmoothRadius*round(IGN(coords*BUFFER_SIZE+2)*9);
		
		dir = float2(1,1);
		smoothLine(
    		coords, 
			refDepth, refNormal, refWp, motionMask,
			centerWeight, centerGiAo,
    		dir, dist,
    		result, aoCount, valid
    	);
        
	// Diag U
		dist = iSmoothRadius*round(IGN(coords*BUFFER_SIZE+3)*9);
		
		dir = float2(1,-1);
		smoothLine(
    		coords, 
			refDepth, refNormal, refWp, motionMask,
			centerWeight, centerGiAo,
    		dir, dist,
    		result, aoCount, valid
    	);
        
    // Final step
    	giAo = result;
		if(valid>0) giAo.rgb = result.rgb/valid;
		else giAo.rgb = centerGiAo.rgb/centerWeight.x;
    	giAo.a = aoCount>0 ? saturate(result.a/aoCount) : 0.0;
    	
		if(valid==0 || aoCount==0) {
			float4 previousAccu = getColorSampler(giSmoothPassSampler,coords);
			if(valid==0) {
				giAo.rgb = previousAccu.rgb;
			}
			if(aoCount==0) {
				giAo.a = previousAccu.a;
			}
			if(iGIRenderScale>3) {
				float4 rawGI = getColorSamplerLod(giPass2Sampler,coords/iGIRenderScale,1.0);
				if(valid==0) {
					giAo.rgb = lerp(giAo.rgb,rawGI.rgb,saturate(iGIRenderScale*0.02));
				}
				if(aoCount==0) {
					giAo.a = lerp(giAo.a,rawGI.a,saturate(iGIRenderScale*0.02));
				}
			}
		}
		

		
        outGI = saturate(giAo);
    }

	float2 getFrameAccu() {
		return float2(iGIFrameAccu,iAOFrameAccu)*(1.0/iGIRenderScale>0.5?lerp(3.0,1.0,(1.0/iGIRenderScale-0.5)*2):lerp(4.0,1.0,saturate((1.0/iGIRenderScale)*3.0)));
	}
	
    void PS_AccuPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {
    
        float2 previousCoords = getPreviousCoords(coords);    
        
        float4 giAO = getColorSampler(giSmooth2PassSampler,coords);
        
        { // reduce sparkles
        	float4 refGiAO = getColorSamplerLod(giSmooth2PassSampler,coords,1.0);
        	float4 diff = abs(refGiAO-giAO);
        	if(maxOf3(diff.rgb)>0.1) giAO = refGiAO;
        }
        

        float4 previousGiMoved = getColorSampler(giPreviousAccuSampler,previousCoords);

        
        float2 op = 1.0/getFrameAccu();

    	float motionDist = 0.5 + distance(coords*BUFFER_SIZE,previousCoords*BUFFER_SIZE);
        float centerDist = 0.5 +distance(0.5*BUFFER_SIZE,coords*BUFFER_SIZE)/(BUFFER_WIDTH*0.5);
        motionDist *= centerDist;
        
    	op.x *= max(1,motionDist*0.1);
    	op.y *= max(1,motionDist*4);
		

        if(maxOf3(previousGiMoved.rgb)<1.0/256) {
            op = 1;
        }

        
		#if !DX9_MODE
		float motionMask = getColorSamplerLod(motionMaskSampler,coords,1.5).x;
		if(fAntiGhosting>0 && motionMask>0) {
			op += motionMask*fAntiGhosting*2;
		}
		#endif
  	
		op = saturate(op);
		
        giAO.rgb = lerp(previousGiMoved.rgb,giAO.rgb, op.x);
        giAO.a = lerp(previousGiMoved.a,giAO.a,op.y);
        
        { // GI Debanding
        	int2 coordsInt = int2(coords*BUFFER_SIZE);
        	float noise = PBN(coordsInt);
        	giAO.rgb += 0.005*getBrightness(1.0-giAO.rgb)*round((noise-0.5)*512.0)/255.0;
        	giAO.rgb = saturate(giAO.rgb);
        }
        
        
        
	    outGI = giAO;
        
        if(bSSR) {
       	 float motionMask = getColorSampler(motionMaskSampler,coords).x;
            float4 ssr = getColorSampler(ssrPassSampler,coords*fSSRRenderScale);
            
        	float4 previousSSRm = getColorSampler(ssrPreviousAccuSampler,previousCoords);
            float4 previousSSR = getColorSampler(ssrPreviousAccuSampler,coords);
            
            float d = distance(ssr.rgb,previousSSR.rgb);
            float dm = distance(ssr.rgb,previousSSRm.rgb);
            float3 previous = lerp(previousSSRm.rgb,previousSSR.rgb,saturate(dm/(d+dm)));
            
            previous *= 0.99;
            ssr.rgb = max(ssr.rgb,previous.rgb*(0.9-motionMask));
            
            float op = saturate(motionMask+1.0/iSSRFrameAccu);
            
            float dp = distance(previous,ssr.rgb);
            op *= lerp(0.5,1,saturate(1.0-dp*2.0));
            
            
            ssr.rgb = lerp(previous,ssr.rgb,op);
            
            outSSR = ssr;
        } else {
            outSSR = 0;
        }
        
    }
    
    float computeAo(float ao,float colorBrightness, float giBrightness, float avgB, float depth) {
        
        ao = 1.0-safePow(1.0-ao,fAOPow);
        
        if(iMemRadius>0 && fAOBoostFromGI>0) {
        	ao = saturate(ao - (1.0-safePow(saturate(giBrightness*2.0),0.5))*fAOBoostFromGI*(1.0-depth)*0.75/0.5);
        }
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        
        
        //ao += giBrightness*fAoProtectGi*4.0;
        
        float inDark = max(0.1,safePow(avgB,0.25));
        ao += (1.0-colorBrightness)*(1.0-colorBrightness)*fAODarkProtect;
        ao += safePow(colorBrightness,2)*fAOLightProtect;
        
        ao = saturate(ao);
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        //ao += pow(giBrightness,2.0)*(1.0-fAoProtectGi)*4.0;
        ao += safePow(giBrightness,2.0)*fAoProtectGi*4.0;
        
        ao += saturate((1.0-colorBrightness)*fAODarkProtect/inDark);
        
        return saturate(ao);
    }
    

    float3 compureResult(
            in float2 coords,
            in float depth,
            in float3 refColor,
            in float4 giAo
        ) {

        float3 color = refColor;
         
        float originalColorBrightness = maxOf3(color);

        if(bRemoveAmbient) {
            color = filterAmbiantLight(color);
        }
        
        
        float3 gi = giAo.rgb;

        float3 giHSV = RGBtoHSV(gi);
        float3 colorHSV = RGBtoHSV(color);
        
        // Base color
        float3 result = color*(bBaseAlternative?1.0:fBaseColor);
        
        // GI
        float avgB = getAverageBrightness();
        
        if(fGIHueBiais>0) {
            float3 resultHSV = RGBtoHSV(saturate(result));
            float3 biaised = resultHSV;
            float hueDist = hueDistance(resultHSV.x,giHSV.x);
            biaised.x = giHSV.x;
            biaised = HSVtoRGB(biaised);
            float r = saturate(1.0-hueDist)*fGIHueBiais*giHSV.z;
            result = lerp(result,biaised,saturate(r));
        }
        
        float darkMerging = fGIFinalMerging*fGIDarkMerging;
    	result += gi * safePow(lerp(refColor,originalColorBrightness,fGIHueBiais),0.25)* (darkMerging*(1.0-originalColorBrightness)+lerp(darkMerging,fGILightMerging,avgB))*0.4*saturate(1.5-maxOf3(result))*(1.0-safePow(saturate(0.99-originalColorBrightness),16));
    	{
    		float3 boostDark = lerp(0,gi*(0.5*darkMerging+(1.0-0.5*darkMerging)*originalColorBrightness),1.0-originalColorBrightness);
    		result += boostDark*darkMerging*0.25;
    		
			float3 lightColor = gi * color;
			float lightColorB = getBrightness(lightColor);
			result = lerp(result,lightColor,lightColorB*fGILightMerging*2*fGIFinalMerging);
			
			result += lerp(0,gi*(0.1+0.9*refColor),originalColorBrightness)*fGILightMerging*fGIFinalMerging;
    	}
        
        if(fGIOverbrightToWhite>0) {
            float b = maxOf3(result);
            if(b>1) {
                result += (b-1)*fGIOverbrightToWhite;
            }
        }
        
        return saturate(result);

    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, 
            out float4 outResult : SV_Target,
            out float4 outGiAccu : SV_Target1,
            out float4 outSsrAccu : SV_Target2
#if !DX9_MODE
            ,out float4 outDepth : SV_Target3
#endif
    ) {
        float2 depth = getDepth(coords);
        float3 refColor = getColor(coords).rgb;

        float4 giAo = getColorSampler(giAccuSampler,coords);

        outGiAccu = giAo;
        outSsrAccu = bSSR ? getColorSampler(ssrAccuSampler,coords) : 0;
#if !DX9_MODE
        outDepth = depth;
#endif

		float m = 1.0-getColorSamplerLod(motionMaskSampler,coords,3).x*0.75;
        outResult = float4(compureResult(coords,depth.x,refColor,giAo),m);
    }
    

    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
    {        
        float3 result = 0;
        
#if !DX9_MODE
        if(bDebugLight) {
            if(distance(coords,fDebugLightPosition.xy)<2*ReShade::PixelSize.x) {
                outPixel = 1;
                return;
            }
        }
#endif
        
        float depth = getDepth(coords).x;
            
        if(iDebug==DEBUG_OFF) {
                    
            result = getColorSampler(resultSampler,coords).rgb;
            
            // AO
            float avgB = getAverageBrightness();
            float resultB = getBrightness(result);

            float4 giAo = getColorSampler(giAccuSampler,coords);
            //float4 giAo = getColorSampler(BFB::sGI,coords);
            float giBrightness = getBrightness(giAo.rgb);
            float ao = giAo.a;
            
            
            ao = computeAo(ao,resultB,giBrightness,avgB,depth);
            
            result *= ao;

               
            // SSR
            if(bSSR && fSSRMerging>0.0) {
                float colorBrightness = getBrightness(result);
                float3 ssr = computeSSR(coords,colorBrightness);
                result *= 1.0-ssr;
                result += ssr;
            }
            

            
            
            // Levels
            result = (result-iBlackLevel/255.0)/((iWhiteLevel-iBlackLevel)/255.0);
            
            // Distance fading

            if(fDistanceFading<1.0 && depth>fDistanceFading) {
                float3 color = getColor(coords).rgb;
                
                float diff = depth-fDistanceFading;
                float max = 1.0-fDistanceFading;
                float ratio = diff/max;
                result = result*(1.0-ratio)+color*ratio;
            }
            
            result = saturate(result);
            
            { // Post color Debanding
                int2 coordsInt = int2(coords*BUFFER_SIZE);
	        	float noise = PBN(coordsInt);
	        	result.rgb += 0.005*getBrightness(1.0-result.rgb)*round((noise-0.5)*512.0)/255.0;
	        	result.rgb = saturate(result.rgb);
	        }
            
        } else if(iDebug==DEBUG_GI) {
            float4 passColor;
            if(false) {
                if(iDebugPass==0) passColor =  getColorSampler(giPass2Sampler,coords/iGIRenderScale);
                if(iDebugPass==1) passColor =  getColorSampler(giSmoothPassSampler,coords);
                
            } else {
                if(iDebugPass==0) passColor =  getColorSampler(giPassSampler,coords/iGIRenderScale);
                if(iDebugPass==1) passColor =  getColorSampler(giPass2Sampler,coords/iGIRenderScale);
            }
            if(iDebugPass==2) passColor =  getColorSampler(giSmooth2PassSampler,coords);
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
                    (safePow(1.0-colorBrightness,2)-safePow(1.0-colorBrightness,4))*2*fGIDarkMerging
                    -(safePow(colorBrightness,2)-safePow(colorBrightness,4))*(1.0-fGILightMerging)
                    )*fGIFinalMerging;
                    
                result += addedGi;
                
                result = saturate(0.5+result-color);
            }

            
        } else if(iDebug==DEBUG_AO) {

            float4 passColor;
            if(false) {
                if(iDebugPass==0) passColor =  getColorSampler(giPass2Sampler,coords/iGIRenderScale);
                if(iDebugPass==1) passColor =  getColorSampler(giSmoothPassSampler,coords);
                
            } else {
                if(iDebugPass==0) passColor =  getColorSampler(giPassSampler,coords/iGIRenderScale);
                if(iDebugPass==1) passColor =  getColorSampler(giPass2Sampler,coords/iGIRenderScale);
            }
            if(iDebugPass==2) passColor =  getColorSampler(giSmooth2PassSampler,coords);
            if(iDebugPass>=3) passColor =  getColorSampler(giAccuSampler,coords);
            
            

            float ao = passColor.a;
            
            if(iDebugPass==3) {
            	float giBrightness = maxOf3(passColor.rgb);
            	ao = saturate(ao - (1.0-safePow(saturate(giBrightness*2.0),0.5))*fAOBoostFromGI*(1.0-depth)*0.75/0.5);
	
		        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
            } 
            
            /*
            if(iDebugPass==3) {
            
                float giBrightness = getBrightness(passColor.rgb);
                if(fAOBoostFromGI>0) {
                    ao *= max(0,1.0-2*fAOBoostFromGI*pow(1.0-giBrightness,2));
                }
                ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
                ao += pow(giBrightness,2.0)*fAoProtectGi*4.0;
                
            } else */
            if(iDebugPass==4) {
                float giBrightness = getBrightness(passColor.rgb);

                float3 color = getColor(coords).rgb;
                if(bRemoveAmbient) {
                    color = filterAmbiantLight(color);
                }
                float colorBrightness = getBrightness(color);
                
                float avgB = getAverageBrightness();
                ao = computeAo(ao,colorBrightness,giBrightness,avgB,depth);
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
            float depth = getDepth(coords).x;
            result = depth;
            if(depth<fWeaponDepth) {
                result = float3(1,0,0);
            }
            else if(isSky(depth)) {
                result = float3(0,1,0);
            }
            
        } else if(iDebug==DEBUG_NORMAL) {
            //result = getColorSampler(normalSampler,coords).rgb;
            result = -getNormal(coords)*0.5+0.5;
            
        } else if(iDebug==DEBUG_SKY) {
            float depth = getDepth(coords).x;
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
            float4 drtf = getDRTF(coords,false);
            float4 rtfs = getColorSampler(RTFSampler,coords);
            if(iDebugPass==0) result =  rtfs.x;
            if(iDebugPass==1) result =  rtfs.y;
            if(iDebugPass==2) result =  rtfs.z;
            if(iDebugPass>=3) result =  rtfs.a;
            if(iDebugPass==4) result = drtf.z*0.004;
            
            result = drtf.z*0.004;

            //float4 brs = getColorSampler(bestRayFillSampler,coords*fGIRenderScale);
           // result = brs.a>0 ? getRayColor(brs.xy).rgb : 0;
            //
            //result = getRayColor(coords).rgb;
            //result = getColorSampler(motionMaskSampler,coords).x;
            //result = getColorSamplerLod(motionMaskSampler,coords,1.5).x;
            //result = getColorSampler(upCoordsSampler,coords).xyz;
            //result = PBN(coords*BUFFER_SIZE);
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT <
        ui_label = "DH_UBER_RT 0.22.0";
        ui_tooltip = 
            "_____________ DH_UBER_RT _____________\n"
            "\n"
            " ver 0.22.0 (2025-09-26)  by AlucardDH\n"
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
            PixelShader = PS_MotionMask;
            RenderTarget = motionMaskTex;
        }
        
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_NormalPass;
            RenderTarget = normalTex;
                        
            ClearRenderTargets = false;
                        
            BlendEnable = true;
            BlendOp = ADD;
            SrcBlend = SRCALPHA;
            SrcBlendAlpha = ONE;
            DestBlend = INVSRCALPHA;
            DestBlendAlpha = ONE;
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
        }
        
        // SSR
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SSR;
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
        
        
        // Merging
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateResult;
            RenderTarget = resultTex;
            RenderTarget1 = giPreviousAccuTex;
            RenderTarget2 = ssrPreviousAccuTex;
#if !DX9_MODE
            RenderTarget3 = previousDepthTex;
#endif
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }
}