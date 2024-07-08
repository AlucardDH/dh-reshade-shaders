////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT 0.18.4-dev (2024-09-06)
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

#ifndef USE_MARTY_LAUNCHPAD
 #define USE_MARTY_LAUNCHPAD 0
#endif


#define SPHERE 0

#if SPHERE
	#ifndef SPHERE_RATIO
	 #define SPHERE_RATIO 8
	#endif
#endif


// HIDDEN PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////
// Should not be modified but can help if you really want to squeeze some FPS at the cost of lower fidelity

// Define the maximum distance a ray can travel
// Default is 1.0 : the full screen/depth, less (0.5) can be enough depending on the game

#define OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO 1.5

// Define is a light smoothing filter on Normal
// Default is 1 (activated)
#define NORMAL_FILTER 0



#define DX9_MODE (__RENDERER__==0x9000)

// Enable ambient light functionality
#define AMBIENT_ON !DX9_MODE
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

#define fGIDistancePower 2.0

// Can be used to fix wrong screen resolution
#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT

#define RENDER_WIDTH INPUT_WIDTH*DH_RENDER_SCALE
#define RENDER_HEIGHT INPUT_HEIGHT*DH_RENDER_SCALE

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
//////////////////////////////////////////////////////////////////////////////

#if USE_MARTY_LAUNCHPAD
namespace Deferred {
	texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
	sampler sMotionVectorsTex { Texture = MotionVectorsTex; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };
}
#else

texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler sTexMotionVectorsSampler { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

#endif
namespace DH_UBER_RT_0184 {

// Textures
#define RTF_FILTER LINEAR
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
    // Roughness Thickness
    texture previousRTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler previousRTFSampler { Texture = previousRTFTex; };
    texture RTFTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler RTFSampler { Texture = RTFTex;
// The magnification, minification and mipmap filtering types.
	// Available values: POINT, LINEAR, ANISOTROPIC
	MagFilter =  RTF_FILTER;
	MinFilter =  RTF_FILTER;
	MipFilter =  RTF_FILTER;

 };
 
    texture bestRayTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler bestRaySampler { Texture = bestRayTex; 
        MagFilter =  POINT;
		MinFilter =  POINT;
		MipFilter =  POINT;
	// Available values: CLAMP, MIRROR, WRAP or REPEAT, BORDER
		AddressU = MIRROR;
		AddressV = MIRROR;
		AddressW = MIRROR;

};
    
    texture previousBestRayTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler previousBestRaySampler { Texture = previousBestRayTex;
    	MagFilter =  POINT;
		MinFilter =  POINT;
		MipFilter =  POINT;
	// Available values: CLAMP, MIRROR, WRAP or REPEAT, BORDER
		AddressU = MIRROR;
		AddressV = MIRROR;
		AddressW = MIRROR;
	 };
   
#if SHPERE
    texture previousSphereTex { Width = RENDER_WIDTH/SPHERE_RATIO; Height = RENDER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler previousSphereSampler { Texture = previousSphereTex;};
    
    texture sphereTex { Width = RENDER_WIDTH/SPHERE_RATIO; Height = RENDER_HEIGHT/SPHERE_RATIO; Format = RGBA8; };
    sampler sphereSampler { Texture = sphereTex;};
#endif

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA16F; };
    sampler normalSampler { Texture = normalTex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
    texture rayColorTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler rayColorSampler { Texture = rayColorTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giPassSampler { Texture = giPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA16F; MipLevels = 6; };
    sampler giAccuSampler { Texture = giAccuTex; MinLOD = 0.0f; MaxLOD = 5.0f;};

    // SSR texture
    texture ssrPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler ssrPassSampler { Texture = ssrPassTex; };

    texture ssrSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler ssrSmoothPassSampler { Texture = ssrSmoothPassTex; };
    
    texture ssrAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler ssrAccuSampler { Texture = ssrAccuTex; };
    
    
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
    > = 0.05;
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
        ui_min = 0; ui_max = 4;
        ui_step = 1;
    > = 2;
    uniform int iTest2 <
		ui_category="Test";
        ui_type = "slider";
        ui_min = 0; ui_max = 64;
        ui_step = 1;
    > = 16;
    uniform bool bTest <ui_category="Test";> = false;
    uniform bool bTest2 <ui_category="Test";> = false;
    uniform bool bTest3 <ui_category="Test";> = false;
    uniform bool bTest4 <ui_category="Test";> = false;
    uniform bool bTest5 <ui_category="Test";> = false;
    uniform bool bTest6 <ui_category="Test";> = false;
    uniform bool bTest7 <ui_category="Test";> = false;
    uniform bool bTest8 <ui_category="Test";> = false;
    uniform bool bTest9 <ui_category="Test";> = false;
    uniform bool bTest10 <ui_category="Test";> = false;
*/
  
// DEBUG 

    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0GI\0AO\0SSR\0Roughness\0Depth\0Normal\0Sky\0Motion\0Ambient light\0Thickness\0";
        ui_tooltip = "Debug the intermediate steps of the shader";
    > = 0;
    
    uniform bool bDebugShowIntensity <
        ui_category = "Debug";
        ui_label = "Show intensity";
    > = false;
    
	uniform bool bSmoothNormals <
        ui_category = "Experimental";
        ui_label = "Smooth Normals";
    > = false;
 
	uniform float fTempoGS <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI Trade-off Ghosting/shimmering";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.100; 
    
    
    uniform float fGIDistanceAttenuation <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI Distance attenuation";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.50;
	
    
    uniform bool bGIOpti <
        ui_category = "Experimental";
        ui_label = "GI Fast";
    > = false; 
    
    uniform bool bRTHQSubPixel <
        ui_category = "Experimental";
        ui_label = "GI High precision sub-pixels";
    > = false; 
    
    uniform bool bGISDF <
        ui_category = "Experimental";
        ui_label = "GI Use Signed Distance Field";
    > = false; 
    
    uniform int iGISDFRadius <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI SDF radius";
    	ui_min = 1; ui_max = 8;
        ui_step = 1;
    > = 1;
    
    uniform int iMemLevel <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI Memory level";
    	ui_min = 0; ui_max = 3;
        ui_step = 1;
    > = 3;
    uniform int iMemRadius <
        ui_type = "slider";
		ui_category="Experimental";
        ui_label = "GI Memory radius";
        ui_min = 1; ui_max = 3;
        ui_step = 1;
    > = 1;

        
    uniform bool bRTShadows <
        ui_category = "Experimental";
        ui_label = "RT Max Deluxe";
    > = false;
    
    uniform float fRTShadowsMinBrightness <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "RT Max Deluxe min brightness";
    	ui_min = 0.1; ui_max = 0.5;
        ui_step = 0.01;
    > = 0.20;
    
    uniform bool bReduceSkyShimmer <
        ui_category = "Experimental";
        ui_label = "Reduce sky shimmer";
    > = false;
    
    
// DEPTH

	uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Depth multiplier";
        ui_min = 0.001; ui_max = 10.00;
        ui_step = 0.001;
        
    > = 1;


    uniform float fSkyDepth <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Sky Depth";
        ui_min = 0.00; ui_max = 1.00;
        ui_step = 0.01;
        ui_tooltip = "Define where the sky starts to prevent if to be affected by the shader";
    > = 0.99;
    
	uniform float fThicknessAdjust <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Thickness adjust";
        ui_min = 0.001; ui_max = 10.00;
        ui_step = 0.001;
    > = 1.0;
    
	uniform float fThicknessAdjust2 <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Thickness adjust 2";
        ui_min = 0.001; ui_max = 10.00;
        ui_step = 0.001;
    > = 1.0;
    
// COMMMON RT
    
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

    uniform int iGIFrameAccu <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "GI Temporal accumulation";
        ui_min = 1; ui_max = 32;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 16;
    
    uniform int iAOFrameAccu <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "AO Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 6;
    
    uniform int iSSRFrameAccu <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "SSR Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 6;

#if !OPTIMIZATION_ONE_LOOP_RT
    uniform int iRTMaxRays <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Max rays...";
        ui_min = 1; ui_max = 6;
        ui_step = 1;
        ui_tooltip = "Maximum number of rays from 1 pixel if the first miss\n"
                    "Lower=Darker image, better performance\n"
                    "Higher=Less noise, brighter image\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    
    uniform int iRTMaxRaysMode <
        ui_type = "combo";
        ui_category = "Common RT";
        ui_label = "... per pixel of";
        ui_items = "Render size\0Target size\0";
    > = 1;
    
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
    > = 0.33;
#endif

    uniform float fNormalRoughness <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Normal roughness";
        ui_min = 0.000; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "";
    > = 0.1;

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
    > = 0.75;
    
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
    
    uniform bool bHudBorderProtection <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Avoid HUD";
        ui_tooltip = "Reduce chances of detecting large lights from the HUD. Disable if you're using RESt or if HUD is hidden";
    > = true;
    
    uniform float fGIAvoidThin <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Avoid thin objects: max thickness";
        ui_tooltip = "Reduce detection of grass or fences";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.0;
    
	uniform float fGIRayColorMinBrightness <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "GI Ray min brightness";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.0;
    
    uniform int iGIRayColorMode <
        ui_type = "combo";
        ui_category = "GI";
        ui_label = "GI Ray brightness mode";
        ui_items = "Crop\0Smoothstep\0Linear\0Gamma\0";
#if DX9_MODE
    > = 0;
#else
    > = 1;
#endif
    
    
    uniform float fSkyColor <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Sky color";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the sky can brighten the scene";
    > = 0.5;
    
    uniform float fSaturationBoost <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Saturation boost";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.0;
    
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

    uniform float fGIHueBiais <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Hue Biais";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much base color can take GI hue.";
    > = 0.30;
    
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
    
    uniform float fGIOverbrightToWhite <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Overbright to white";
        ui_min = 0.0; ui_max = 5.0;
        ui_step = 0.001;
    > = 0.25;
    
// AO
    uniform float fAOBoostFromGI <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Boost from GI";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.25;
    
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
        ui_tooltip = "Define the intensity of AO";
    > = 1.00;
    
    uniform int iAODistance <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Distance";
        ui_min = 0; ui_max = BUFFER_WIDTH;
        ui_step = 1;
    > = BUFFER_WIDTH/8;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Pow";
        ui_min = 0.001; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 1.0;
    
    uniform float fAOLightProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Light protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of bright areas to avoid washed out highlights";
    > = 0.50;  
    
    uniform float fAODarkProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Dark protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of dark areas to avoid totally black and unplayable parts";
    > = 0.15;

    uniform float fAoProtectGi <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "GI protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.25;
    


// SSR
    uniform bool bSSR <
        ui_category = "SSR";
        ui_label = "Enable SSR";
        ui_tooltip = "Toggle SSR";
    > = false;
    uniform bool bSSRHQSubPixel <
        ui_category = "SSR";
        ui_label = "SSR High precision sub-pixels";
    > = true;
    uniform bool bSSRRinR <
        ui_category = "SSR";
        ui_label = "Reflections in reflection";
    > = false;
    
    uniform float fSSRSharpen <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "Sharpen reflection";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Counter SSR smoothing when denoising is enabled";
    > = 0.25;

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
    > = 0.5;

    uniform float fMergingSSR <
        ui_type = "slider";
        ui_category = "SSR";
        ui_label = "SSR Intensity";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define this intensity of the Screan Space Reflection.";
    > = 0.350;
// Denoising
    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Radius";
        ui_min = 0; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Define the max distance of smoothing.\n"
                    "Higher:less noise, less performances\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1;
    
    uniform float fSmoothDepth <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Depth";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.5;
    
    uniform bool bSSRFilter <
        ui_category = "Denoising";
        ui_label = "Filter SSR";
    > = false;
    
    
    /*
    uniform int iSmoothStep <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "Step";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Compromise smoothing by skipping pixels in the smoothing and using lower quality LOD.\n"
                    "Higher:less noise, can smooth surfaces that should not be mixed\n"
                    "This has no impact on performances :)";
    > = 4;
    */
    
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
        ui_label = "Base color";
        ui_min = 0.0; ui_max = 2.0;
        ui_step = 0.01;
        ui_tooltip = "Simple multiplier for the base image.";
    > = 1.0;
    
    uniform bool bBaseAlternative <
        ui_category = "Merging";
        ui_label = "Base color alternative method";
    > = false;

    uniform int iBlackLevel <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Black level ";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 0;
    
    uniform int iWhiteLevel <
        ui_type = "slider";
        ui_category = "Merging";
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

    int halfIndex(float2 coords) {
        int2 coordsInt = (coords * RENDER_SIZE)%2;
        return coordsInt.x==coordsInt.y?0:1;
    }
    
    int quadIndex(float2 coords) {
        int2 coordsInt = (coords * RENDER_SIZE)%2;
        return coordsInt.x+coordsInt.y*2;
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
    
    float getPureness(float3 rgb) {
        return maxOf3(rgb)-minOf3(rgb);
    }
    
    float getBrightness(float3 rgb) {
    	return maxOf3(rgb);
    }

// Screen

	float getSkyDepth() {
		return fSkyDepth*fDepthMultiplier;
	}

	float3 getNormal(float2 coords) {
		float3 normal = (tex2Dlod(normalSampler,float4(coords,0,0)).xyz-0.5)*2;
		return normal;
	}

    float getDepth(float2 coords) {
    	return ReShade::GetLinearizedDepth(coords)*fDepthMultiplier;
    }
    
    
    float4 getRTF(float2 coords) {
        return getColorSampler(RTFSampler,coords);
    }
    
    float4 getDRTF(float2 coords) {
    	
        float4 drtf = getDepth(coords);
        drtf.yzw = getRTF(coords).xyz;
        if(fNormalRoughness>0 && drtf.x<=getSkyDepth()) {
            float roughness = drtf.y;
        	drtf.x += drtf.x*roughness*fNormalRoughness*0.1*fDepthMultiplier;
        }
        drtf.z = (0.01+drtf.z)*drtf.x*320*fThicknessAdjust;
        drtf.z *= (0.25+drtf.x);
        
        return drtf;
    }
    
    bool inScreen(float3 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0
            && coords.z>=0.0 && coords.z<=fDepthMultiplier;
    }
    
    bool inScreen(float2 coords) {
        return coords.x>=0.0 && coords.x<=1.0
            && coords.y>=0.0 && coords.y<=1.0;
    }
    

    
    float3 getWorldPositionForNormal(float2 coords,bool ignoreRoughness) {
        float depth = getDepth(coords);
        if(!ignoreRoughness && fNormalRoughness>0 && depth<=getSkyDepth()) {
            float roughness = getRTF(coords).x;
            if(bSmoothNormals) roughness *= 1.5;
        	depth += depth*roughness*fNormalRoughness*0.1;
        }
        
        float3 result = float3((coords-0.5)*depth,depth);
        result *= BUFFER_SIZE3;
        return result;
    }
    
    float3 getWorldPosition(float2 coords,float depth) {
        float3 result = float3((coords-0.5)*depth,depth);
        result *= BUFFER_SIZE3;
        return result;
    }

    float3 getScreenPosition(float3 wp) {
        float3 result = wp/BUFFER_SIZE3;
        result.xy /= result.z;
        return float3(result.xy+0.5,result.z);
    }

    float4 computeNormal(float2 coords,float3 offset,bool ignoreRoughness) {
        float3 posCenter = getWorldPositionForNormal(coords,ignoreRoughness);
        float3 posNorth  = getWorldPositionForNormal(coords - offset.zy,ignoreRoughness);
        float3 posEast   = getWorldPositionForNormal(coords + offset.xz,ignoreRoughness);
        
        return float4(normalize(cross(posCenter - posNorth, posCenter - posEast)),1.0);
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
        v = abs((getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rg-0.5)*2.0);
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
        v = getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rgb;
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE)+random+framecount;
		v = randomTriple(coords,seed);
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
#if USE_MARTY_LAUNCHPAD
		float2 mv = getColorSampler(Deferred::sMotionVectorsTex,coords).xy;
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
    
    	if(refDepth>getSkyDepth()) {
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
            float2 step = orientation*ReShade::PixelSize*d/DH_RENDER_SCALE;
            
            if(validPos) {
                currentCoords = coords+step;
                depth = getDepth(currentCoords);
                if(depth>getSkyDepth() && sky==1) {
                	sky = 1.0-float(d)/iThicknessRadius;
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
                if(depth>getSkyDepth() && sky==1) {
                	sky = 1.0-float(d)/iThicknessRadius;
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
    

    float sdfPass(float2 coords, float refDepth,float thickness) {
        
        float startDepth = refDepth-float(iGISDFRadius)/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
        
        float3 startWp = getWorldPosition(coords,startDepth);
        
        float sdf = iGISDFRadius;
        
        float depth;
        float2 currentCoords;
        float3 currentWp;
        
        float2 orientation = normalize(randomCouple(coords*PI)-0.5);
        
        [loop]
        for(int d=0;d<=iGISDFRadius;d+=1) {
            float2 step = orientation*ReShade::PixelSize*d/DH_RENDER_SCALE;
            
            {
                currentCoords = coords+step;
                depth = getDepth(currentCoords);
                currentWp = getWorldPosition(currentCoords,depth);
                sdf = min(sdf,distance(currentWp,startWp));
            }
        
            if(d>0) {
                currentCoords = coords-step;
                depth = getDepth(currentCoords);
                currentWp = getWorldPosition(currentCoords,depth);
                sdf = min(sdf,distance(currentWp,startWp));
            }
        }        
        
        
    	return sdf/iGISDFRadius;
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
        RTFS.a = min(RTFS.a,0.25+previousRTFS.a);

        if(bGISDF) {
            RTFS.z = sdfPass(coords,depth,RTFS.y);
            RTFS.z = previousRTFS.z>0 ? min(RTFS.z,previousRTFS.z*1.05) : RTFS.z;
        } else {
            RTFS.z = 1;
        }
        
        outRTFS = RTFS;
    }
    
    
    void PS_SavePreviousBestRayPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outPixel : SV_Target0) {
        outPixel = getColorSampler(bestRaySampler,coords);
    }

#if AMBIENT_ON
    void PS_SavePreviousAmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {
        outAmbient = getColorSampler(ambientSampler,CENTER);
    }
    
    
    
    void PS_AmbientPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outAmbient : SV_Target0) {
        if(!bRemoveAmbient || !bRemoveAmbientAuto) discard;

        float4 previous = getColorSampler(previousAmbientSampler,CENTER);
        float3 result = previous.rgb;
        float b = maxOf3(result);
        
        bool first = framecount%60==0;
        if(b<0.1) {
            first = true;
            result = 1;
            b = 1;
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
                   float2 c = currentCoords+rand*stepDim;
                    float3 color = getColor(c).rgb;
                    b = maxOf3(color);
                    if(b>0.1 && b<bestB) {
                    
                        bestCoords = c;
                        result = min(result,color);
                        bestB = b;
                    }
                }
            }
            size = stepSize;
            numSteps = 8;
            stepSize = size.x/numSteps.x;
        }
        
        float opacity = first && bestB<0.5 ? 0.5 : saturate(1.0-bestB*5)*0.1;
        result = min(previous.rgb+0.01,result);
        outAmbient = float4(result, first ? 0.1 : 0.01);
    }
    
    float3 getRemovedAmbiantColor() {
        if(bRemoveAmbientAuto) {
            float3 color = getColorSampler(ambientSampler,float2(0.5,0.5)).rgb;
            color += color.x;
            return color;
        } else {
            return cSourceAmbientLightColor;
        }
    }
    
    float3 filterAmbiantLight(float3 sourceColor) {
        float3 color = sourceColor;
        if(bRemoveAmbient) {
            float3 ral = getRemovedAmbiantColor();
            float3 removedTint = ral - minOf3(ral); 

            color -= removedTint;
            color = saturate(color);
            
            color = lerp(sourceColor,color,fSourceAmbientIntensity);
            
            if(bAddAmbient) {
                float b = getBrightness(color);
                color = saturate(color+pow(1.0-b,4.0)*cTargetAmbientLightColor);
            }
        }
        return color;
    }
#endif

	float4 mulByA(float4 v) {
		v.rgb *= v.a;
		return v;
	}

    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
        
        float3 offset = float3(ReShade::PixelSize, 0.0);
        
        float4 normal = computeNormal(coords,offset,false);
        
		if(bSmoothNormals) {
        	float3 offset2 = offset * 7.5*(1.0-getDepth(coords));
            float4 normalTop = computeNormal(coords-offset2.zy,offset,true);
            float4 normalBottom = computeNormal(coords+offset2.zy,offset,true);
            float4 normalLeft = computeNormal(coords-offset2.xz,offset,true);
            float4 normalRight = computeNormal(coords+offset2.xz,offset,true);
            
        	normalTop.a *= smoothstep(1,0,distance(normal.xyz,normalTop.xyz)*1.5);
        	normalBottom.a *= smoothstep(1,0,distance(normal.xyz,normalBottom.xyz)*1.5);
        	normalLeft.a *= smoothstep(1,0,distance(normal.xyz,normalLeft.xyz)*1.5);
        	normalRight.a *= smoothstep(1,0,distance(normal.xyz,normalRight.xyz)*1.5);
            
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
        
    }
    
    float3 rampColor(float3 color) {
    	float b = getBrightness(color);
        float originalB = b;
        
        if(iGIRayColorMode==1) { // smoothstep
            b *= smoothstep(fGIRayColorMinBrightness,1.0,b);
        } else if(iGIRayColorMode==2) { // linear
            b *= saturate(b-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness);
        } else if(iGIRayColorMode==3) { // gamma
            b *= safePow(saturate(b-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness),2.2);
        }
        
        
        return originalB>0 ? color * b / originalB : 0;
    }
    
    void PS_RayColorPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {

        float3 color = getColor(coords).rgb;
 
#if AMBIENT_ON
        if(iRemoveAmbientMode<2) {  
            color = filterAmbiantLight(color);
        }
#endif
		
		float2 previousCoords = getPreviousCoords(coords);
		float3 colorHSV = RGBtoHSV(color);
		int lod = 1;
		while((1.0-colorHSV.y)*colorHSV.z>0.7 && lod<=5) {
			color = getColorSamplerLod(resultSampler,previousCoords,lod).rgb;
			colorHSV = RGBtoHSV(color);
			
			colorHSV.z = 0.9;
			color = HSVtoRGB(colorHSV);
			
			lod ++;
		}
		
		if(fSaturationBoost>0 && colorHSV.z*colorHSV.y>0.1) {
			colorHSV.y = saturate(colorHSV.y+fSaturationBoost);
			color = HSVtoRGB(colorHSV);
		}
		
		if(fGIBounce>0.0) {
			float3 previousColor = getColorSampler(giAccuSampler,previousCoords).rgb;
			float b = getBrightness(color);
			color = saturate(color+previousColor*fGIBounce*(1.0-b)*(0.5+b));
			
		}
        
        
        
        
		float3 result = rampColor(color);        
          
        if(fGIDarkAmplify>0) {
        	float3 colorHSV = RGBtoHSV(result);
        	colorHSV.z = saturate(colorHSV.z+fGIDarkAmplify*colorHSV.z*(1.0-colorHSV.z)*10);
        	result = HSVtoRGB(colorHSV);
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
    
    bool hit(float3 currentWp, float3 screenWp, float depth, float thickness) {
    	if(fGIAvoidThin>0 && thickness<depth*100*fGIAvoidThin) return false;
    	return currentWp.z>=screenWp.z && currentWp.z<=screenWp.z+thickness;
    }
    
    float3 getDebugLightWp() {
    	return getWorldPosition(fDebugLightPosition.xy,bDebugLightZAtDepth ? getDepth(fDebugLightPosition.xy)*0.99 : fDebugLightPosition.z);
    }     	

    bool hitLight(float3 currentWp,float3 targetWp) {
        return distance(targetWp,currentWp)<=iDebugLightSize*2;
    }
    
    bool hitDebugLight(float3 currentWp) {
        return hitLight(getDebugLightWp(),currentWp);
    }
    
    bool isBehind(float3 refWp,float3 refNormal, float3 hitWp) {
		return distance(refWp-refNormal*0.5,hitWp)>distance(refWp,hitWp);
	}
	
    RTOUT trace(float3 refWp,float3 incrementVector,float startDepth,bool ssr,bool lightTarget,float3 targetWp) {
    
        RTOUT result;
        result.status = RT_MISSED;
        
        float3 currentWp = refWp;
        float3 refNormal = getNormal(getScreenPosition(currentWp).xy);
        
        
		incrementVector = normalize(incrementVector);
		
		if(lightTarget) {
			float d = dot(refNormal,-incrementVector);
			if(d<0) {
				result.status = RT_HIT_BEHIND;
    			result.wp = refWp;
            
        		return result;
			}
		}		
		
		incrementVector *= 0.1;
		
        float deltaZ = 0.0;
		
        currentWp += incrementVector;
        float3 screenCoords = getScreenPosition(currentWp);
        
        bool outScreen = !inScreen(screenCoords);
        if(outScreen) {
        	result.status = RT_MISSED_FAST;
            return result;
        }
        
        float4 DRTF = getDRTF(screenCoords.xy);
        if(DRTF.x>getSkyDepth()) {
            result.status = RT_HIT_SKY;
            result.wp = currentWp;
        }  
        
        float3 screenWp = getWorldPosition(screenCoords.xy,DRTF.x);
        
        bool outSource = !hit(currentWp, screenWp, DRTF.x,DRTF.z);
        
        
		int step = -1;
		
		while(fNormalRoughness>0 && !outSource && step<4)  {
			currentWp += incrementVector;
			screenCoords = getScreenPosition(currentWp);
			screenWp = getWorldPosition(screenCoords.xy,DRTF.x);
			DRTF = getDRTF(screenCoords.xy);
			outSource = !hit(currentWp, screenWp, DRTF.x,DRTF.z);
			step++;
        }
        
		if(!outSource) {
			result.status = RT_MISSED_FAST;
		    return result;
        }
        
        
        bool behindBefore = false;
        float3 previousWp = currentWp;
        float3 previousScreenWp = screenWp;
        float thickness = 0;
        float3 startBehindWp = 0;
        
		
		float maxDist = lightTarget ? distance(currentWp,targetWp) : sqrt(BUFFER_WIDTH*BUFFER_WIDTH+BUFFER_HEIGHT*BUFFER_HEIGHT);
		float forcedLength = max(16.0,maxDist/16.0);
		while(distance(refWp,currentWp)<maxDist && step<16*(ssr?8:1)) {
			step++;
			if(length(incrementVector)>forcedLength) {
				incrementVector = normalize(incrementVector)*forcedLength;
			}
			float dTarget = lightTarget ? distance(currentWp,targetWp) : 0;
            currentWp += incrementVector;
            
            float3 screenCoords = getScreenPosition(currentWp);
            
            bool outScreen = !inScreen(screenCoords);
            if(outScreen) {
            	currentWp -= incrementVector;
            	if(ssr) {
            		currentWp -= incrementVector;
            		incrementVector *= abs(previousWp.z-previousScreenWp.z)/incrementVector.z;
            		currentWp += incrementVector;
            		continue;
            	}
                break;
            }
            
            
            DRTF = getDRTF(screenCoords.xy);
            
            float3 screenWp = getWorldPosition(screenCoords.xy,DRTF.x);
            bool behind = currentWp.z>screenWp.z;
                        
            if(behind) {
            	if(thickness==0) {
            		thickness += length(incrementVector)*0.5*3*fThicknessAdjust2;
            		startBehindWp = currentWp;
            	} else {
            		thickness += length(incrementVector)*3*fThicknessAdjust2;
            	}
            }
            
            DRTF.z += thickness*DRTF.x;
            
            if(DRTF.x>getSkyDepth() && result.status<=RT_HIT_SKY) {
                result.status = RT_HIT_SKY;
                result.wp = currentWp;
            }
            
            
            //int crossed = crossing(deltaZbefore,deltaZ);
            
            if(lightTarget && hitLight(currentWp,targetWp)) {
				result.status = RT_HIT_DEBUG_LIGHT;
                result.wp = targetWp;
                        
            	return result;
            }
            
            bool isHit = hit(currentWp, screenWp, DRTF.x,DRTF.z);
            
			if(isHit) {
            	result.status = behindBefore ? RT_HIT_BEHIND : RT_HIT;
        		result.wp = currentWp;
                    
        		return result;
            }
            
            
            if(ssr) {
            	deltaZ = screenWp.z-currentWp.z;
        		float l = max(0.5,abs(deltaZ)*0.1);
        		incrementVector = normalize(incrementVector)*l;
        	} else  {
				float2 r = randomCouple(screenCoords.xy);
	            float l = 1.00+DRTF.x+r.y;
	            if(bGIOpti) {
				    l += step*r.x*0.5;
			    }
			    
			    
			    if(bGISDF) {
	    			float sdfDistance = DRTF.w*iGISDFRadius;
	    			float sdfRefDistance = screenWp.z-iGISDFRadius;
	    			float curDist = screenWp.z-currentWp.z;
	    			if(abs(currentWp.z-sdfRefDistance)<sdfDistance) {
	    				sdfDistance = max(1,(sdfDistance-(sdfRefDistance-curDist)));
	    				l = sdfDistance;
	                    incrementVector = normalize(incrementVector);
	    			}
	    			
	    		}
	            
	            incrementVector *= l;
            }
                
            
            
            previousScreenWp = screenWp;
        	previousWp = currentWp;
            behindBefore = behind;
            if(!behind) {
            	thickness = 0;
            }
            
            //step++;

        }
        
        
        if(lightTarget) {
            result.status = RT_HIT_DEBUG_LIGHT;
            result.wp = targetWp;
                        
            return result;
        }
        
        
        
        if(ssr && result.status<RT_HIT_GUESS) {
            result.wp = currentWp;
        }
        
        return result;
    }

// GI
	

	/*
	int getIndexRGB(float2 pixelSize, float2 coords) {
		int2 px = (coords/pixelSize);
		return (px.x%3+px.y%3+framecount)%3;
	}
	*/
	
	float getMissingColor(float3 ref,float3 color) {
		if(ref.r<=ref.g && ref.r<=ref.b) {
			return color.r;
		}
		if(ref.g<=ref.r && ref.g<=ref.b) {
			return color.g;
		}
		return color.b;
	}
	
	void handleHit(
		in float3 refWp, in float3 refNormal, in float3 lightVector, in bool doTargetLight, in float3 targetColor, in RTOUT hitPosition, 
		inout float3 sky, inout float4 bestRay, inout float mergedAO, inout int hits, inout float4 mergedGiColor,
		in bool skipPixel, in float3 refColor
	) {
		
		float3 coords = getScreenPosition(refWp);
        float2 pixelSize = ReShade::PixelSize/DH_RENDER_SCALE;
		float3 screenCoords = getScreenPosition(hitPosition.wp);
        
        //float pixelIndex = getIndexRGB(pixelSize,coords.xy);
        
        float4 giColor = 0.0;
        if(hitPosition.status <= RT_MISSED || !inScreen(screenCoords.xy)) {
	
		} else if(hitPosition.status==RT_HIT_SKY) {
            giColor = getColor(screenCoords.xy);
            float b = getBrightness(giColor.rgb);
			if(b>0) giColor *= fSkyColor/b;
			sky = max(sky,giColor.rgb);
            
        } else if(hitPosition.status>=0 ) {
        
        	float mul = 1;
        
        	float dist = distance(hitPosition.wp,refWp);
            	
        	if(hitPosition.status!=RT_HIT_DEBUG_LIGHT && (hitPosition.status==RT_HIT_BEHIND || isBehind(refWp,refNormal,hitPosition.wp))) {

				giColor = 0;
        		
    		} else {
    			
    			if(doTargetLight && (bDebugLight && bDebugLightOnly)) {
            		if(hitPosition.status==RT_HIT_DEBUG_LIGHT) {
            			giColor = targetColor;
            		} else {
            			giColor = 0;
            		}
            	} else {
            		giColor = getRayColor(screenCoords.xy);
            		
    			}
    			
    			float d = dot(lightVector,-refNormal);
    			if(d<-0.5) mul = 0;
    			else mul *= saturate(d+0.5);
    			
    			{
    				float3 hitNormal = getNormal(screenCoords.xy);
    				float d = dot(hitNormal,-refNormal);
    				//if(d<-fTest) mul = 0;
    				 mul *= saturate(d+1.5);
    			}
    			
    			mul *= (1.0-safePow(saturate(1.0-(1.0-pow(fGIDistanceAttenuation,0.075))*(1.0-coords.z)*2000.0/dist),2.0));
    			
    			/*
				{
    			
	    			float d2 = dist*fGIDistanceAttenuation*0.05;
	    			d2 *= (1.0-coords.z)*10;
					d2 *= d2;
					mul *= saturate(1.0/d2);
				
				}
				*/
				giColor.rgb *= mul;

				float b = getBrightness(giColor.rgb);
				if(b>=bestRay.a) {
					bestRay = float4(hitPosition.wp,b);
				}
    			
			}

			
			if(!doTargetLight) {
	            float ao = dist/(iAODistance*coords.z);
	            mergedAO += saturate(ao);
	            hits+=1.0;
            }
            
            mergedGiColor.rgb = max(mergedGiColor.rgb,giColor.rgb);
    		mergedGiColor.a = getBrightness(mergedGiColor.rgb);
        }
	}

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outBestRay : SV_Target1) {
        
		int subWidth = 1.0/DH_RENDER_SCALE;
		int subMax = subWidth*subWidth;
		int subCoordsIndex = framecount%subMax;
        
        float depth = getDepth(coords);
        if(depth>getSkyDepth()) {
            outGI = 0.0;
            outBestRay = 0.0;
            return;
        }
        
        
        float3 refWp = getWorldPosition(coords,depth);
        float3 refNormal = getNormal(coords);
        float3 refColor = getColor(coords).rgb;
        
        float2 previousCoords = getPreviousCoords(coords);
        float motionDist = distance(previousCoords*BUFFER_SIZE,coords*BUFFER_SIZE);
        float4 previousFrame = getColorSampler(giAccuSampler,previousCoords);
        
        
        
        bool skipPixel = 
			(iCheckerboardRT==1 && halfIndex(coords)!=framecount%2)
        	|| (iCheckerboardRT==2 && quadIndex(coords)!=framecount%4);
		
		float3 screenCoords;
        
        float3 sky = 0.0;
        float4 mergedGiColor = 0.0;
        float mergedAO = 0.0;
        float4 bestRay = 0;
        
        float hits = 0;
        float aoHits = 0;
        int rays = 0;
        
        float2 subCoords = coords;
        
        float3 rand;
        
#if !TEX_NOISE
        uint seed = getPixelIndex(subCoords,RENDER_SIZE);
#endif
        
    #if !OPTIMIZATION_ONE_LOOP_RT
    
    	int maxRays = iRTMaxRays*(iRTMaxRaysMode?subMax:1);
    	int topMaxRays = iRTMaxRays*(iRTMaxRaysMode?subMax:1)*OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO;
        if(skipPixel) maxRays = 1;
        
        [loop]
        for(rays=0;
				rays<maxRays 
				&& maxRays<=topMaxRays
				&& mergedGiColor.a<fRTMinRayBrightness;
			rays++
		) {
        
        	if(bDebugLight && bDebugLightOnly && rays>0) {
    			break;
    		}
    #else
        int maxRays = 0;
        int iRTMaxRaysMode = 1;
    #endif
    		
    		
    		if(DH_RENDER_SCALE<1.0) {
	    		subCoordsIndex = (subCoordsIndex+1)%subMax;
	    		int2 delta = 0;
	    		delta.x = subCoordsIndex%subWidth;
	    		delta.y = subCoordsIndex/subWidth;
		        subCoords = coords+ReShade::PixelSize*(delta-subWidth*0.5);
		        depth = getDepth(subCoords);
		        if(bRTHQSubPixel) {
					refWp = getWorldPosition(subCoords,depth);
                	refNormal = getNormal(subCoords);
                }
	        }
#if TEX_NOISE
			rand = randomTriple(subCoords+(0.05*(rays+framecount)));
#else
			rand = randomTriple(subCoords,seed);
#endif
			
			bool doTargetLight = rays==0 && bDebugLight;
			float3 targetWp;
			float3 targetColor;
			float3 lightVector;
			if(doTargetLight) {
				rand = normalize(rand-0.5);
            	targetWp = getDebugLightWp();           
            	targetWp += rand*iDebugLightSize*0.9;
            	lightVector = normalize(targetWp-refWp);
            	targetColor = fDebugLightColor;
			} else if(skipPixel || (bRTShadows && rays%2==0)) {
				float3 targetCoords = rand;
				targetColor = getRayColor(targetCoords.xy);
				float intensity = getBrightness(targetColor);
				
				if(intensity>=fRTShadowsMinBrightness) {
					targetCoords.z = getDepth(targetCoords.xy);
					targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
					lightVector = normalize(targetWp-refWp);
					doTargetLight = true;
				} else {
					rand = normalize(rand-0.5);
            		lightVector = rand;
				}
				
			} else {
				rand = normalize(rand-0.5);
            	lightVector = rand;
			}

            RTOUT hitPosition = trace(refWp,lightVector,depth,false,doTargetLight,targetWp);
            
            if(hitPosition.status == RT_MISSED_FAST) {
                maxRays++;
    #if !OPTIMIZATION_ONE_LOOP_RT
                continue;
    #endif
            }
                
            handleHit(
				refWp, refNormal, lightVector, doTargetLight, targetColor, hitPosition, 
				sky, bestRay, mergedAO, hits, mergedGiColor,
				true,refColor
			);
            
			
                
    #if !OPTIMIZATION_ONE_LOOP_RT
        }
    #endif
    
        float2 pixelSize = ReShade::PixelSize/DH_RENDER_SCALE;
        

    	if(!skipPixel && iMemLevel>0 && !(bDebugLight && bDebugLightOnly)) {

        
    		float4 previousBestRay = 0;
    			
   		 if(!skipPixel && iMemLevel==1) {
   		 	previousBestRay = getColorSampler(previousBestRaySampler,coords);
				
    			
			} else if(iMemLevel==2) {
    			int2 delta;
    			int r = iMemRadius*iMemRadius;
    			for(delta.x=-r;delta.x<=r;delta.x+=1) {
    				for(delta.y=-r;delta.y<=r;delta.y+=1) {
    					rand.xy = normalize(frac(abs(rand.xy)*137)-0.5)*2.0;
		    			float2 currentCoords = coords+delta*pixelSize*32*rand.xy;
    					currentCoords += (rand.xy*BUFFER_SIZE*0.25)/BUFFER_SIZE;
    					
    					if(!inScreen(currentCoords)) continue;
    					float4 ray = getColorSampler(previousBestRaySampler,currentCoords);
    					if(ray.a>=previousBestRay.a && ray.z<=fSkyDepth) {
    						previousBestRay = ray;
    					}
    				}
    			}
    			
    		} else if(iMemLevel>=3) {

    			int2 delta;
    			int r = iMemRadius;
				
    			for(delta.x=-r;delta.x<=r;delta.x+=1) {
    				for(delta.y=-r+abs(delta.x);delta.y<=r-+abs(delta.x);delta.y+=1) {
    					rand.xy = normalize(frac(abs(rand.xy)*137)-0.5);    					
    					float2 currentCoords = coords+delta*3*pixelSize*64*rand.xy;
    					
	    				if(!inScreen(currentCoords)) continue;
			    		
    					float4 ray = getColorSampler(previousBestRaySampler,currentCoords);
    					float dist = 0;
    					if(bHudBorderProtection) {
    						dist = distance(ray.xy*BUFFER_SIZE,float2(0.5,0.5)*BUFFER_SIZE);
    					}
    					ray.xy += (bHudBorderProtection?0.5+dist*0.01:1)*rand.xy*BUFFER_SIZE*0.015*rand.z/BUFFER_SIZE;
    					
    					
    					
                        float3 targetCoords = ray.xyz;
                        targetCoords.z = getDepth(targetCoords.xy);
    					bool doTargetLight = targetCoords.z<=fSkyDepth;
    					
                        float3 targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
                        
						float3 lightVector = normalize(targetWp-refWp);
						float3 targetColor = getRayColor(targetCoords.xy).rgb;
					
			    		RTOUT hitPosition = trace(refWp,lightVector,depth,false,doTargetLight,targetWp);
			    		
			    		handleHit(
							refWp, refNormal, lightVector, doTargetLight, targetColor, hitPosition, 
							sky, bestRay, mergedAO, hits, mergedGiColor,
							skipPixel,refColor
						);
						
    				}
    			}
    		}
    		
			if(iMemLevel<3 && previousBestRay.a>=0.15) {
			
		    	previousBestRay.xy += ((rand.xy)*BUFFER_SIZE*0.003)/BUFFER_SIZE;
		    			
				float3 targetCoords = previousBestRay.xyz;
				targetCoords.xy += targetCoords.xy-getPreviousCoords(targetCoords.xy);
                targetCoords.z = getDepth(targetCoords.xy);
                bool doTargetLight = targetCoords.z<=fSkyDepth;
                
    					
                float3 targetWp = getWorldPosition(targetCoords.xy,targetCoords.z);
                
				float3 lightVector = normalize(targetWp-refWp);
				float3 targetColor = getRayColor(targetCoords.xy).rgb;
				
	    		RTOUT hitPosition = trace(refWp,lightVector,depth,false,doTargetLight,targetWp);
	            handleHit(
					refWp, refNormal, lightVector, doTargetLight, targetColor, hitPosition, 
					sky, bestRay, mergedAO, hits, mergedGiColor,
					skipPixel,refColor
				);
            }
            
    	}
    
    	if(motionDist>3) { 
    		float pb = getBrightness(previousFrame.rgb);
    		float b = getBrightness(mergedGiColor.rgb);
    		if(pb>b && b>0) {
    			mergedGiColor.rgb *= pb/b;
    		}
    	}

    	mergedGiColor.rgb = max(mergedGiColor.rgb,sky);
    	if(skipPixel) {
    		mergedGiColor.rgb = max(mergedGiColor.rgb,previousFrame.rgb*0.9);
    	}
    	
    	if(hits<=0) {
            mergedAO = 1.0;
        } else {
        	mergedAO = saturate(mergedAO/hits);
        }
                
        float opacity = saturate(1.0/iAOFrameAccu);     
        if(motionDist>3) { 
    		opacity = saturate(opacity*4);
    	}
        mergedAO = lerp(previousFrame.a,mergedAO,opacity);
		
		bestRay.xyz = getScreenPosition(bestRay.xyz);
        outBestRay = bestRay;
        outGI = float4(mergedGiColor.rgb,mergedAO);
    }

// SSR
    void PS_SSRLightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!bSSR || fMergingSSR==0.0) {
            outColor = 0.0;
            return;
        }
        
        int subWidth = 1.0/DH_RENDER_SCALE;
		int subMax = subWidth*subWidth;
		int subCoordsIndex = framecount%subMax;
		int2 delta = 0;
        
        float2 subCoords = coords;
        
        if(!bSSRHQSubPixel && DH_RENDER_SCALE<1.0) {
        	subCoordsIndex = (subCoordsIndex*PI)%subMax;
    		delta.x = subCoordsIndex%subWidth;
    		delta.y = subCoordsIndex/subWidth;
	        subCoords = coords+ReShade::PixelSize*(delta-subWidth*0.5);
        }
            
        float depth = getDepth(subCoords);
        
        if(depth>getSkyDepth()) {
            outColor = 0.0;
        } else {
        
            float3 result = 0;
            float weightSum = 0;
            
            [loop]
            for(int rays=0;rays<(bSSRHQSubPixel && DH_RENDER_SCALE<1.0 ?subMax:1);rays++) {
        		
        		if(bSSRHQSubPixel && DH_RENDER_SCALE<1.0) {
    	    		subCoordsIndex = (subCoordsIndex+1)%subMax;
    	    		delta.x = subCoordsIndex%subWidth;
    	    		delta.y = subCoordsIndex/subWidth;
    		        subCoords = coords+ReShade::PixelSize*(delta-subWidth*0.5);
    		        depth = getDepth(subCoords);
    	        }
                
                float3 targetWp = getWorldPosition(subCoords,depth);         
                float3 targetNormal = getNormal(subCoords);
                
        
                float3 lightVector = reflect(targetWp,targetNormal)*0.01;
                
                RTOUT hitPosition = trace(targetWp,lightVector,depth,true,false,0);
				float3 screenPosition = getScreenPosition(hitPosition.wp.xyz);
                    
                if(hitPosition.status<RT_HIT_SKY) {
                	float3 c = getColorSampler(ssrAccuSampler,coords).rgb;
                	weightSum += 0.5;
                	result += 0.5*c;
                } else {
                    float3 screenPosition = getScreenPosition(hitPosition.wp.xyz);
                    float2 previousCoords = getPreviousCoords(screenPosition.xy);
                    float3 c = getColorSampler(resultSampler,previousCoords).rgb;
                    
                    if(bSSRRinR) c = max(c,getColorSampler(ssrAccuSampler,previousCoords).rgb*0.8);
                    float w = getBrightness(c)*100.0+1.0;
                    
                    
                    result += c*w;
                    weightSum += w;
                
                }
            }

            if(weightSum>0) {
                outColor = float4(result/weightSum,(bSSRHQSubPixel?1:subMax)*weightSum/32.0);
            } else {
            	float3 c = getColorSampler(ssrAccuSampler,coords).rgb;
                outColor = float4(c*0.9,0.5);
            }
        }
        
            
    }
    
    void smooth(
        sampler sourceGISampler,
        sampler sourceSSRSampler,
        float2 coords, out float4 outGI, out float4 outSSR,bool firstPass
    ) {
        float2 pixelSize = ReShade::PixelSize/DH_RENDER_SCALE;
        
        float refDepth = getDepth(coords);
        if(refDepth>getSkyDepth()) {
            outGI = getColor(coords);
            outSSR = float4(0,0,0,1);
            return;
        }
        
        float3 refNormal = getNormal(coords);  
 
        float4 giAo = 0.0;
        float4 ssr = 0.0;
        
        
        float3 weightSum; // gi, ao, ssr
        
        float2 previousCoords = getPreviousCoords(coords);
        
        float4 refColor = firstPass && iGIFrameAccu>1
            ? getColorSampler(giAccuSampler,previousCoords)
            : 0;
            
        
        float4 previousColor = firstPass ? getColorSampler(giAccuSampler,coords) : 0;
        float4 previousSSRm = bSSR && firstPass ? getColorSampler(ssrAccuSampler,previousCoords) : 0;
		float4 previousSSR = bSSR && firstPass ? getColorSampler(ssrAccuSampler,coords) : 0;

        
        float4 refSSR = getColorSampler(sourceSSRSampler,coords);
        
        float refB = getBrightness(refColor.rgb);
        
        float2 currentCoords;
        
        int smoothRadius = iSmoothRadius;
                        
        int2 delta;        
        [loop]
        for(delta.x=-smoothRadius;delta.x<=smoothRadius;delta.x++) {
            [loop]
            for(delta.y=-smoothRadius;delta.y<=smoothRadius;delta.y++) {
                float dist = length(delta);
                
				currentCoords = coords+delta*pixelSize.xy*2.0;
                
                
                
                float depth = getDepth(currentCoords);
                if(depth>getSkyDepth()) continue;
                

                
                float4 curGiAo = getColorSampler(sourceGISampler,currentCoords);
                
                
                //float b = getBrightness(curGiAo.rgb);
                
                // Distance weight | gi,ao,ssr 
                float3 weight = 1+max(0,1.45*iSmoothRadius-dist);
                weight.x *= 0.5+abs(1.2*getBrightness(curGiAo.rgb)-getBrightness(previousColor.rgb));
                
                { // Normal weight
                	
	                float3 normal = getNormal(currentCoords);
	                float3 t = normal-refNormal;
	                float dist2 = max(dot(t,t), 0.0);
	                float nw = safePow(1.0/(0.1+dist2),1.5);
	                weight.xy *= nw*nw*nw;
	                weight.z *= safePow(saturate(dot(normal,refNormal)),500*(1.0-refDepth));
                }
                
                
                {
                	float aoDist = 1.0-abs(curGiAo.a-previousColor.a);
	                weight.y *= 0.5+aoDist*10;
                }
	                    
                
                { // Depth weight
                    
                    float dw = max(0,1.0-abs(refDepth-depth)*100*fSmoothDepth);
                    weight *= dw*dw;
                }
                
                giAo.rgb += curGiAo.rgb*weight.x;
                giAo.a += curGiAo.a*weight.y;               
                
                if(bSSR && (bSSRFilter || dist<1)) {
                    currentCoords = coords+delta*pixelSize.xy;
                    
                    float4 ssrColor = getColorSampler(sourceSSRSampler,currentCoords);
                    float ssrB = maxOf3(ssrColor.rgb);
                    if(ssrB==0) {
                    	weight.z = 0;
                    }
                    
                    if(firstPass) ssrColor.rgb *= ssrColor.a<1.0?0.8:1;
                    
                    weight.z *= 0.1+maxOf3(ssrColor.rgb);
                    
                    if(firstPass) {
                        weight.z *= ssrColor.a;
                        
                        float colorDist = 1.0-maxOf3(abs(ssrColor.rgb-previousSSRm.rgb));
	                    weight.z *= 0.5+colorDist*20;
                    }
                    
                    if(fSSRSharpen>0) {
                    	float diff = maxOf3(abs(refSSR-ssrColor));
                    	weight.z *= saturate(1.0-diff*(1.0-ssrB)*fSSRSharpen*25.0);
                    }
                    
                    if(firstPass && dist>0) {
                    	weight.z *= maxOf3(saturate(refSSR.rgb-ssrColor.rgb));
                    }
                    
                    ssr += ssrColor.rgb*weight.z;

                } else {
                	weight.z = 0;
                }
                
                weightSum += weight;
                
                        
            } // end for y
        } // end for x
        
        if(weightSum.x>0) {
        	giAo.rgb /= weightSum.x;
        } else {
        	giAo.rgb = 0;
        }
        
    	
        if(weightSum.y>0) {
        	giAo.a /= weightSum.y;
        } else {
        	giAo.a = 1.0;
        }
                
        if(weightSum.z>0) {
        	ssr /=  weightSum.z;
        } else {
        	ssr = 0;
        }
        
        
        if(firstPass) {
	        
            float2 op = 1.0/float2(iGIFrameAccu,iAOFrameAccu);
        	
            if(op.x<1)  {
                float motionDistance = distance(previousCoords*BUFFER_SIZE,coords*BUFFER_SIZE);
                if(motionDistance>3) op = saturate(op+motionDistance*fTempoGS*0.1);	                
            }
            
        	outGI = float4(lerp(refColor.rgb,giAo.rgb,op.x),lerp(refColor.a,giAo.a,op.y));

         
        	outGI = float4(lerp(refColor.rgb,giAo.rgb,op.x),lerp(refColor.a,giAo.a,op.y));
            

            if(bSSR) {
                op = 1.0/iSSRFrameAccu;
                    
                float3 ssrColor;
                
                {
                    float b = getBrightness(ssr.rgb);
                    float pb = getBrightness(previousSSRm.rgb);
                    op += abs(b-pb)*0.4;
                    
                    float motionDistance = max(0,0.065*(distance(previousCoords.xy*BUFFER_SIZE,coords.xy*BUFFER_SIZE)-1.0));
                    float colorDist = fTempoGS*motionDistance*maxOf3(abs(previousSSR.rgb-ssr.rgb));
                    op = saturate(op+colorDist*24);
                    
                    
                }	
                
                
                if(weightSum.z>0) {
	                ssrColor = lerp(
                        previousSSRm.rgb,
                        ssr.rgb,
                        saturate(op.x*(1.2-maxOf3(ssr.rgb)))
                    );
                } else {
                    ssrColor = previousSSRm.rgb;
                }
                
                outSSR = float4(ssrColor,1.0);
            } else {
                outSSR = 0;
            }
        } else {
        	outGI = saturate(giAo);
            
            if(bSSR) {
                outSSR = float4(ssr.rgb,1.0);
            } else {
            	outSSR = 0;
            }
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
    	
        //giBrightness = smoothstep(0,0.5,giBrightness);
        
        //ao = fAOMultiplier-(1.0-ao)*fAOMultiplier;
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
		if(fAOBoostFromGI>0) {
			ao = max(0,ao-(1.0-giBrightness)*fAOBoostFromGI);
        }

        ao = (safePow(ao,fAOPow));
        
        ao += giBrightness*fAoProtectGi*4.0;
        
		ao += (1.0-colorBrightness)*fAODarkProtect;
        ao += colorBrightness*fAOLightProtect;
        
		ao = saturate(ao);
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        return ao;
    }
    
    float3 computeSSR(float2 coords,float brightness) {
        float4 ssr = getColorSampler(ssrAccuSampler,coords);
        if(ssr.a==0) return 0;
        
        float3 ssrHSV = RGBtoHSV(ssr.rgb);
        
        float ssrBrightness = getBrightness(ssr.rgb);
        float ssrChroma = ssrHSV.y;
        
        float colorPreservation = lerp(1,safePow(brightness,2),1.0-safePow(1.0-brightness,10));
        
        ssr = lerp(ssr,ssr*0.5,saturate(ssrBrightness-ssrChroma));
        
        float roughness = getRTF(coords).x;
        
        float rCoef = lerp(1.0,saturate(1.0-roughness*10),fMergingRoughness);
        float coef = fMergingSSR*(1.0-brightness)*rCoef;
        
        return ssr.rgb*coef;
            
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outResult : SV_Target) {
        float depth = getDepth(coords);
        float3 refColor = getColor(coords).rgb;
        float refB = getBrightness(refColor);
        float3 color = refColor;
        float3 colorHSV = RGBtoHSV(color);
        
        if(depth>getSkyDepth()) {
            outResult = float4(color,1.0);
        } else {   
            float originalColorBrightness = maxOf3(color);
#if AMBIENT_ON
            if(iRemoveAmbientMode==0 || iRemoveAmbientMode==2) {
                color = filterAmbiantLight(color);
            }
#endif
            
            
            
            
            float4 passColor = getColorSampler(giAccuSampler,coords);
            
            float3 gi = passColor.rgb;
            float3 giHSV = RGBtoHSV(gi);
            float giBrightness =  getBrightness(gi);            
            colorHSV = RGBtoHSV(color);
           
            float colorBrightness = getBrightness(color);
            	
            // Base color
            float3 result = color;
            float p = getPureness(result);
            
            float4 RTFS = getColorSampler(RTFSampler,coords);
            
            	
            // GI
            result += 
            	(result
					+pow(result,3.0)*fGILightMerging*8.0
					+sqrt(colorBrightness)*(1.0-lerp(colorBrightness*gi*4.0,result,(1.0-colorBrightness)*fGIHueBiais*6.0))*fGIDarkMerging*2.0
				)
				*fGIFinalMerging
				*(1.0-pow(colorHSV.z,0.3))
				*gi
				*(1+giHSV.y*0.25);
            
            
        	// Overbright
        	if(fGIOverbrightToWhite>0) {
        		float b = maxOf3(result);
	        	if(b>1) {
	        		result += (b-1)*fGIOverbrightToWhite;
	        	}
        	}
            
            // Mixing
            //result = lerp(color,result,fGIFinalMerging);
            
            // Apply AO after GI
            {
                float resultB = getBrightness(result);
                float ao = passColor.a;
                ao = computeAo(ao,resultB,giBrightness);
                result *= ao;
            }
            
            if(bReduceSkyShimmer && RTFS.a>0) result = lerp(refColor,saturate(result),smoothstep(0,1,RTFS.a));
            
            outResult = float4(saturate(result),1.0);
            
            
        }
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
            
            float3 resultHSV = RGBtoHSV(result);
            float depth = getDepth(coords);
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
            if(fDistanceFading<1.0 && depth>fDistanceFading*fDepthMultiplier) {
                float diff = depth/fDepthMultiplier-fDistanceFading;
                float max = 1.0-fDistanceFading;
                float ratio = diff/max;
                result = result*(1.0-ratio)+color*ratio;
            }
            
            result = saturate(result);
            
        } else if(iDebug==DEBUG_GI) {
            float4 passColor =  getColorSampler(giAccuSampler,coords);
            float3 gi =  passColor.rgb;
            
            if(bDebugShowIntensity) {
            	float3 color = getColor(coords).rgb;
#if AMBIENT_ON
	            if(iRemoveAmbientMode==0 || iRemoveAmbientMode==2) {
	                color = filterAmbiantLight(color);
	            }
#endif
            
            	color = saturate(color*(bBaseAlternative?1:fBaseColor));
            	
        		float colorBrightness = getBrightness(color);
        		float giBrightness = getBrightness(gi);
				
            	float3 r = 0;
            	// Dark areas
	            
	            // Light areas
	            result += color+r*gi*saturate(colorBrightness*fGILightMerging*2)*min(giBrightness,1.0-colorBrightness);
            
            	if(fGIOverbrightToWhite>0) {
	        		float b = maxOf3(colorBrightness+r);
		        	if(b>1) {
		        		r += (b-1)*fGIOverbrightToWhite;
		        	}
	        	}
            	
            	r *= fGIFinalMerging;
            	
            	r = saturate(r);
            	
            	gi = r;
            }
                    	
        	result = gi;
            
        } else if(iDebug==DEBUG_AO) {
            float4 passColor =  getColorSampler(giAccuSampler,coords);
            float ao = passColor.a;
            float giBrightness = getBrightness(passColor.rgb);
	        if(bDebugShowIntensity) {

	            
	            float3 color = getColor(coords).rgb;
	            float colorBrightness = getBrightness(color);
	            
	            ao = computeAo(ao,colorBrightness,giBrightness);
	            
	            result = ao;
            } else {
            	//giBrightness = smoothstep(0,0.5,giBrightness);
		        
                ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
    			if(fAOBoostFromGI>0) {
					ao = max(0,ao-(1.0-giBrightness)*fAOBoostFromGI);
		        }
        		
    
    			ao = safePow(ao,fAOPow);
		        ao = saturate(ao);
		        ao = saturate(ao+giBrightness*fAoProtectGi*4.0);
				ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
				result = ao;
			}
            
        } else if(iDebug==DEBUG_SSR) {
        	float4 ssr = getColorSampler(ssrAccuSampler,coords);
        	
        	if(bDebugShowIntensity) {
        		float3 color = getColorSampler(resultSampler,coords).rgb;
        		float colorBrightness = getBrightness(color);
				ssr = computeSSR(coords,colorBrightness);
        	}
        	result = ssr.rgb;
            
        } else if(iDebug==DEBUG_ROUGHNESS) {
            float3 RTF = getColorSampler(RTFSampler,coords).xyz;
            
            result = RTF.x;
            //result = RTF.z;
        } else if(iDebug==DEBUG_DEPTH) {
            float depth = getDepth(coords);
            result = depth;
            
        } else if(iDebug==DEBUG_NORMAL) {
            result = getColorSampler(normalSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_SKY) {
            float depth = getDepth(coords);
            result = depth>getSkyDepth()?1.0:0.0;
            
            result = (getColorSampler(bestRaySampler,coords).rgb+1)*0.5;          
            //result = getColorSampler(sphereSampler,coords).rgb;  
      
        } else if(iDebug==DEBUG_MOTION) {
            float2  motion = getPreviousCoords(coords);
            motion = 0.5+(motion-coords)*25;
            result = float3(motion,0.5);
            
        } else if(iDebug==DEBUG_AMBIENT) {
#if AMBIENT_ON
            result = getRemovedAmbiantColor();
#else   
            result = 0;
#endif    
			float3 c = getColorSampler(bestRaySampler,coords).rgb;
			result = getColor(c.xy).rgb;
			
        } else if(iDebug==DEBUG_THICKNESS) {
            float4 drtf = getDRTF(coords);
            
            result = drtf.z;
      
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT <
        ui_label = "DH_UBER_RT 0.18.4-dev";
        ui_tooltip = 
            "_____________ DH_UBER_RT _____________\n"
            "\n"
            " ver 0.18.4-dev (2024-09-06)  by AlucardDH\n"
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

		pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SavePreviousBestRayPass;
            RenderTarget = previousBestRayTex;
        }
      
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