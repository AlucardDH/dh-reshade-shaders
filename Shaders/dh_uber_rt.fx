////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_RT 0.16.7.4-dev (2023-12-19)
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://alucarddh.github.io
// Join my Discord server for news, request, bug reports or help : https://discord.gg/V9HgyBRgMW
//
// Credits
// Björn Ottosson for OKLAB ColorSpace https://bottosson.github.io/posts/oklab/
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

#define OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO 3

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
#define BUFFER_SIZE3 int3(INPUT_WIDTH,INPUT_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier)


// MACROS /////////////////////////////////////////////////////////////////
// Don't touch this
#define getNormal(c) (tex2Dlod(normalSampler,float4((c).xy,0,0)).xyz-0.5)*2
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4((c).xy,0,0))
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4((c).xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4((c).xy,0,0))
#define maxOf3(a) max(max(a.x,a.y),a.z)
#define minOf3(a) min(min(a.x,a.y),a.z)
#define avgOf3(a) (((a).x+(a).y+(a).z)/3.0)
#define CENTER float2(0.5,0.5)
//////////////////////////////////////////////////////////////////////////////

texture texMotionVectors { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler sTexMotionVectorsSampler { Texture = texMotionVectors; AddressU = Clamp; AddressV = Clamp; MipFilter = Point; MinFilter = Point; MagFilter = Point; };

namespace DH_UBER_RT_01673 {

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
    // Roughness Thickness
    texture previousRTTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler previousRTSampler { Texture = previousRTTex; };
    texture RTTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler RTSampler { Texture = RTTex; };

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA16F; };
    sampler normalSampler { Texture = normalTex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; MipLevels = 6;  };
    sampler resultSampler { Texture = resultTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    // RTGI textures
    texture rayColorTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler rayColorSampler { Texture = rayColorTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture lightSourceTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler lightSourceSampler { Texture = lightSourceTex; };
    
    texture giPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giPassSampler { Texture = giPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};

    texture giSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 6; };
    sampler giSmoothPassSampler { Texture = giSmoothPassTex; MinLOD = 0.0f; MaxLOD = 5.0f;};
    
    texture giAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA16F; };
    sampler giAccuSampler { Texture = giAccuTex; };

    // SSR textures
    texture ssrPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler ssrPassSampler { Texture = ssrPassTex; };

    texture ssrSmoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler ssrSmoothPassSampler { Texture = ssrSmoothPassTex; };
    
    texture ssrAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler ssrAccuSampler { Texture = ssrAccuTex; };
    
// Structs
    struct RTOUT {
        float3 wp;
        float3 DRT;
        float deltaZ;
        float3 color;
        float status;
    };
    

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
    > = 0.130;
    uniform float fTest2 <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 25.0;
        ui_step = 0.001;
    > = 15.0;
    uniform int iTest <
        ui_type = "slider";
        ui_min = 0; ui_max = 64;
        ui_step = 1;
    > = 5;
    uniform bool bTest2 = false;
    uniform bool bTest3 = false;
    uniform bool bTest4 = false;
    uniform bool bTest5 = false;
    uniform float fTest3 <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.130;
*/

    
    uniform float fGIRayColorMinBrightness <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI Ray min brightness";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.0;
    
    uniform int iGIRayColorMode <
        ui_type = "combo";
        ui_category = "Experimental";
        ui_label = "GI Ray brightness mode";
        ui_items = "Crop\0Smoothstep\0Linear\0Gamma\0";
    > = 1;
    
    uniform float fAOBoostFromGI <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "AO boost from GI";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.2;
    
    uniform bool bGIMinThickness <
        ui_category = "Experimental";
        ui_label = "GI Min thickness";
    > = false;
    
    uniform float fGIMinThickness <
        ui_type = "slider";
        ui_category = "Experimental";
        ui_label = "GI Min thickness";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.150;
    
// DEBUG 

    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0GI\0AO\0SSR\0Roughness\0Depth\0Normal\0Sky\0Motion\0Ambient light\0Thickness\0";
        ui_tooltip = "Debug the intermediate steps of the shader";
    > = 0;
    
// DEPTH

    uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Depth multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.01;
        ui_tooltip = "Multiply the depth returned by the game\n"
                    "Can help to make mutitple shaders work together";
    > = 1.0;

    uniform float fSkyDepth <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Sky Depth";
        ui_min = 0.00; ui_max = 1.00;
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
    
    uniform int iRTCheckHitPrecision <
        ui_category = "Common RT";
        ui_type = "slider";
        ui_label = "RT Hit precision";
        ui_min = 1; ui_max = 6;
        ui_step = 1;
        ui_tooltip = "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES\n";
    > = 1;
    
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
    > = 4;
    
    uniform int iRayStepPrecision <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Step Precision";
        ui_min = 0; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the length of the steps during ray tracing.\n"
                    "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES";
    > = 16;

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

    uniform bool bGIFastResponse <
        ui_category = "GI";
        ui_label = "Fast response";
        ui_tooltip = "Trade-off between faster GI responsiveness vs noise";
    > = true;
    
    uniform bool bGIAvoidThin <
        ui_category = "GI";
        ui_label = "Avoid thin objects";
        ui_tooltip = "Reduce detection of grass or fences";
    > = true;
    
    
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
    > = 0.50;
    
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
    > = 0.5;
    
        
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
    > = 0.25;
    
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
    > = false;
    
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
    > = BUFFER_WIDTH/8;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Pow";
        ui_min = 0.001; ui_max = 2.0;
        ui_step = 0.001;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 1.25;
    
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
    > = 0.20;

    uniform float fAoProtectGi <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "GI protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.50;
    


    // SSR
    uniform bool bSSR <
        ui_category = "SSR";
        ui_label = "Enable SSR";
        ui_tooltip = "Toggle SSR";
    > = false;
    

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
    > = 4;
    
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
        ui_step = 1;
    > = 5;
    
    uniform int iWhiteLevel <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "White level";
        ui_min = 0; ui_max = 255;
        ui_step = 1;
    > = 255;

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

    float toLinear(float c){return(c<=0.04045)?c/12.92:pow((c+0.055)/1.055,2.4);}
    float3 toLinear(float3 c){return float3(toLinear(c.r),toLinear(c.g),toLinear(c.b));}
    float toSRGB(float c){return(c<0.0031308?c*12.92:1.055*pow(c,0.41666)-0.055);}
    float3 toSRGB(float3 c){return float3(toSRGB(c.r),toSRGB(c.g),toSRGB(c.b));}

    float3 RGBtoOKLab(float3 rgb) {
        float3 c = toLinear(rgb);
        
        float l = 0.4121656120f * c.r + 0.5362752080f * c.g + 0.0514575653f * c.b;
        float m = 0.2118591070f * c.r + 0.6807189584f * c.g + 0.1074065790f * c.b;
        float s = 0.0883097947f * c.r + 0.2818474174f * c.g + 0.6302613616f * c.b;

        float l_ = pow(l, 1./3.);
        float m_ = pow(m, 1./3.);
        float s_ = pow(s, 1./3.);

        float3 labResult;
        labResult.x = 0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_;
        labResult.y = 1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_;
        labResult.z = 0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_;
        
        //labResult.yz /= labResult.x + 1.;
        
        return labResult;
    }
    
    float3 OKLabToLch(float3 oklab) {
        float3 oklch = oklab;
        oklch.y = sqrt(oklab.y*oklab.y+oklab.z*oklab.z);
        oklch.z = atan2(oklab.z,oklab.y);
        return oklch;
    }
    
    float3 OKLchToLab(float3 oklch) {
        float3 oklab = oklch;
        oklab.y = oklch.y*cos(oklch.z);
        oklab.z = oklch.y*sin(oklch.z);
        return oklab;
    }

    float3 OKLabtoRGB(float3 c) {
        //c.yz *= c.x + 1.;

        float l0 = c.x + 0.3963377774f * c.y + 0.2158037573f * c.z;
        float m0 = c.x - 0.1055613458f * c.y - 0.0638541728f * c.z;
        float s0 = c.x - 0.0894841775f * c.y - 1.2914855480f * c.z;

        float l = l0*l0*l0;
        float m = m0*m0*m0;
        float s = s0*s0*s0;

        float3 rgbResult;
        rgbResult.r = + 4.0767245293f*l - 3.3072168827f*m + 0.2307590544f*s;
        rgbResult.g = - 1.2681437731f*l + 2.6093323231f*m - 0.3411344290f*s;
        rgbResult.b = - 0.0041119885f*l - 0.7034763098f*m + 1.7068625689f*s;
        
        
        return toSRGB(rgbResult);
    }
    
    float3 OKLchtoRGB(float3 c) {
        return OKLabtoRGB(OKLchToLab(c));
    }
    
    float3 RGBtoOKLch(float3 c) {
        return OKLabToLch(RGBtoOKLab(c));
    }
    
    
    float4 getColorOKLch(sampler s, float2 coords) {
        float4 color = getColorSampler(s,coords);
        color.xyz = OKLabToLch(RGBtoOKLab(color.rgb));
        return color;
    }
    
    float4 getColorOKLch(float2 coords) {
        return getColorOKLch(ReShade::BackBuffer,coords);
    }
    
    float4 getColorOKLch(sampler s, float2 coords, float lod) {
        float4 color = getColorSamplerLod(s,coords,lod);
        color.xyz = OKLabToLch(RGBtoOKLab(color.rgb));
        return color;
    }
    
    float getRGBPureness(float3 rgb) {
        return maxOf3(rgb)-minOf3(rgb);
    }

// Screen

    float getDepth(float2 coords) {
        return ReShade::GetLinearizedDepth(coords);
    }
    
    float getStrictDepth(float2 coords) {
        int2 coordsInts = coords*BUFFER_SIZE;
        coords = float2(coordsInts) / BUFFER_SIZE;
        
        return ReShade::GetLinearizedDepth(coords);
    }
    
    float3 getDRT(float2 coords) {
        float3 drt = getDepth(coords);
        drt.yz = getColorSampler(RTSampler,coords).xy;
        drt.z = (0.1+drt.z)*12.5*drt.x*25;
        return drt;
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
        float3 drt = getDRT(coords);
        if(fNormalRoughness>0) {
            drt.x += drt.x*drt.y*fNormalRoughness*0.1;
        }
        float3 result = float3((coords-0.5)*drt.x,drt.x);
        if(drt.x<fWeaponDepth) {
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
  
        float refB = RGBtoOKLab(refColor).x;      
        roughness *= safePow(refB,0.5);
        roughness *= safePow(1.0-refB,2.0);
        
        // roughness decrease with depth
        roughness = refDepth>0.5 ? 0 : lerp(roughness,0,refDepth/0.5);
        
        return roughness;
    }

    float thicknessPass(float2 coords, float refDepth) {

        int iThicknessRadius = 4;//max(1,min(iTest,8));
        
        float2 thickness = 0;
        float previousXdepth = refDepth;
        float previousYdepth = refDepth;
        float depthLimit = refDepth*0.015;
        float depth;
        float2 currentCoords;
        
        float2 orientation = normalize(randomCouple(coords*PI)-0.5);
        
        bool validPos = true;
        bool validNeg = true;
        
        [loop]
        for(int d=1;d<=iThicknessRadius;d++) {
            float2 step = orientation*ReShade::PixelSize.x*d/DH_RENDER_SCALE;
            
            if(validPos) {
                currentCoords = coords+step;
                depth = ReShade::GetLinearizedDepth(currentCoords);
                if(depth-previousXdepth<=depthLimit) {
                    thickness.x += 1;
                    previousXdepth = depth;
                } else {
                    validPos = false;
                }
            }
        
            if(validNeg) {
                currentCoords = coords-step;
                depth = ReShade::GetLinearizedDepth(currentCoords);
                if(depth-previousYdepth<=depthLimit) {
                    thickness.y += 1;
                    previousYdepth = depth;
                } else {
                    validNeg = false;
                }
            }
        }        
        
        thickness /= iThicknessRadius;
        
        
        return (thickness.x+thickness.y)/2;
    }
    
    
    void PS_RT_save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRT : SV_Target0) {
        outRT = getColorSampler(RTSampler,coords);
    }    
    
    void PS_DRT(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRT : SV_Target0) {
        float2 RT;
        float depth = ReShade::GetLinearizedDepth(coords);
        
        float2 previousCoords = getPreviousCoords(coords);
        float2 diff = (previousCoords-coords);
        
        RT.x = roughnessPass(coords,depth);
        RT.y += thicknessPass(coords,depth);
        
        float3 previousRT = getColorSampler(previousRTSampler,previousCoords).xyz;
        RT.y = lerp(previousRT.y,RT.y,0.33);
        
        outRT = float4(RT,0,1);
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
                float b = RGBtoOKLab(color).x;
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

        float3 color = getColor(coords).rgb;
#if AMBIENT_ON
        if(iRemoveAmbientMode<2) {  
            color = filterAmbiantLight(color);
        }
#endif

        float3 colorOKLch = RGBtoOKLch(color);
        
        
        if(fGIDarkAmplify>0) {
            colorOKLch.x *= 1.0+fGIDarkAmplify*(1.0-colorOKLch.x)*2.0;
        }
        
        if(iGIRayColorMode==1) { // smoothstep
            colorOKLch.x *= smoothstep(fGIRayColorMinBrightness,1.0,colorOKLch.x);
        } else if(iGIRayColorMode==2) { // linear
            colorOKLch.x *= (colorOKLch.x-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness);
        } else if(iGIRayColorMode==3) { // gamma
            colorOKLch.x *= safePow((colorOKLch.x-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness),2.2);
        }
        
        float3 result = OKLchtoRGB(colorOKLch);
        

        if(fGIBounce>0.0) {
            float2 previousCoords = getPreviousCoords(coords);
            float3 gi = getColorSampler(giAccuSampler,previousCoords).rgb;
            result += gi*min(0.5,1.0-result.x)*fGIBounce;
        }
        
        if(maxOf3(result)<fGIRayColorMinBrightness) {
            result = 0; 
        }
        
        outColor = float4(result,1.0);
        
    }
    
    void PS_LSPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {

        float3 color = getColor(coords).rgb;
#if AMBIENT_ON
        if(iRemoveAmbientMode<2) {  
            color = filterAmbiantLight(color);
        }
#endif

        float3 colorOKLch = RGBtoOKLch(color);
        
        
        if(fGIDarkAmplify>0) {
            colorOKLch.x *= 1.0+fGIDarkAmplify*(1.0-colorOKLch.x)*2.0;
        }
        
        if(iGIRayColorMode==1) { // smoothstep
            colorOKLch.x *= smoothstep(fGIRayColorMinBrightness,1.0,colorOKLch.x);
        } else if(iGIRayColorMode==2) { // linear
            colorOKLch.x *= (colorOKLch.x-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness);
        } else if(iGIRayColorMode==3) { // gamma
            colorOKLch.x *= safePow((colorOKLch.x-fGIRayColorMinBrightness)/(1.0-fGIRayColorMinBrightness),2.2);
        }
        
        float3 result = OKLchtoRGB(colorOKLch);
        

        if(fGIBounce>0.0) {
            float2 previousCoords = getPreviousCoords(coords);
            float3 gi = getColorSampler(giAccuSampler,previousCoords).rgb;
            result += gi*min(0.5,1.0-result.x)*fGIBounce;
        }
        
        if(maxOf3(result)<fGIRayColorMinBrightness) {
            result = 0; 
        }
        
        outColor = float4(result,1.0);
        
    }

    bool hittingSSR(float deltaZ, float3 DRT, float3 incrementVector) {
        if(length(incrementVector)<1) {
            return false;
        }
        return (deltaZ<=0 && -deltaZ<DRT.z*0.1);
    }
    
    bool hittingGI(float deltaZ, float thickness) {
        return deltaZ<=0.5 && -deltaZ<thickness;
    }
    
    int crossing(float deltaZbefore, float deltaZ) {      
        if(deltaZ<=0 && deltaZbefore>0) return -1;
        if(deltaZ>=0 && deltaZbefore<0) return 1;
        return  0;
    }
    
    RTOUT trace(float3 refWp,float3 incrementVector,float startDepth,bool ssr) {
    
        RTOUT result;
        
        int rayStepPrecision = ssr ? 600*startDepth : iRayStepPrecision;
        float stepRatio;
        float stepLength = 0.01/(1.0+rayStepPrecision);
        
        if(!ssr) stepLength *= 0.5;
        
        incrementVector *= stepLength;
        
        incrementVector *= 1+2000*startDepth;
        
        float3 currentWp = refWp;
        
        float3 refNormal = getNormal(getScreenPosition(currentWp).xy);

        float deltaZ = 0.0;
        float deltaZbefore = 0.0;
        
        float3 lastSky = 0.0;
        
        
        bool startWeapon = startDepth<fWeaponDepth;
        float weaponLimit = fWeaponDepth*BUFFER_SIZE3.z;
        
        bool outSource = false;
        
        int step = 0;
        
        do {
            currentWp += incrementVector;
            
            float3 screenCoords = getScreenPosition(currentWp);
            
            bool outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            
            float3 DRT = getDRT(screenCoords.xy);
            float3 screenWp = getWorldPosition(screenCoords.xy,DRT.x);
            
            deltaZ = screenWp.z-currentWp.z;
            
            if(DRT.x>fSkyDepth) {
                lastSky = currentWp;
            }            
            
            float t = getColorSampler(RTSampler,screenCoords.xy).y;
            if(outScreen || deltaZ<0) {
                result.status = RT_MISSED_FAST;
                return result;
                
            } else if(step) {
                outSource = abs(deltaZ)>deltaZbefore;
            }
            
            if(!step) deltaZbefore = abs(deltaZ);
            step++;
            

            float2 r = randomCouple(screenCoords.xy);
            stepRatio = 1.00+DRT.x+r.x;
            
            incrementVector *= stepRatio;
            

        } while(!outSource && step<8);
            
        deltaZbefore = deltaZ;
        
        float3 crossedWp = 0;
        
        int searching = -1;
        float screenZBefore = 0;
        
        result.status = RT_MISSED;
        
        int maxSearching = ssr?32:iRTCheckHitPrecision;
        
        [loop]
        do {

            currentWp += incrementVector;
            
            float3 screenCoords = getScreenPosition(currentWp);
            
            bool outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            if(outScreen) {
                break;
            }
            
            float3 DRT = getDRT(screenCoords.xy);
            float3 screenWp = getWorldPosition(screenCoords.xy,DRT.x);
            
            deltaZ = screenWp.z-currentWp.z;
            
            if(DRT.x>fSkyDepth && result.status<RT_HIT_SKY) {
                result.status = RT_HIT_SKY;
                result.wp = currentWp;
            }
            
            
            bool crossed = crossing(
                deltaZbefore,
                deltaZ
            );
            
            if(crossed) {
                crossedWp = currentWp;
                
                searching += 1;
                
                if(ssr ? hittingSSR(deltaZ,DRT,incrementVector) : hittingGI(deltaZ,DRT.z)) {
                    if(bGIAvoidThin && !ssr && DRT.z<0.2*currentWp.z) {
                    } else {
                        result.status = RT_HIT;
                        result.DRT = DRT;
                        result.deltaZ = deltaZ;
                        result.wp = currentWp;
                    }
                }
                
                if(searching<maxSearching) {
                    currentWp -= incrementVector;
                    incrementVector *= 0.5;
                    deltaZ = deltaZbefore;

                } else if(result.status==RT_HIT) {
                    return result;

                } else {
                    searching = -1;
                }

            }
            
            deltaZbefore = deltaZ;
            screenZBefore = screenWp.z;
            
            if(searching==-1) {
                float2 r = randomCouple(screenCoords.xy);
                
                stepRatio = 1.00+DRT.x+r.y;
                
                incrementVector *= stepRatio;
            }
            step++;

        } while(step<32);

        if(ssr && result.status<RT_HIT) {
            result.wp = currentWp;
        }
        return result;
    }

// GI

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
        float3 DRT = getDRT(coords);
        if(DRT.x>fSkyDepth) {
            outGI = 0.0;
            return;
        }
        
        float3 refWp = getWorldPosition(coords,DRT.x);
        float3 refNormal = getNormal(coords);
        
        float2 previousCoords = getPreviousCoords(coords);
        float4 previousFrame = getColorSampler(giAccuSampler,previousCoords);
        float3 previousLch = RGBtoOKLch(previousFrame.rgb);
        
#if DX9_MODE
        // No checkerboard rendering on DX9 for now
#else
        if(iCheckerboardRT==1 && halfIndex(coords)!=framecount%2) {
            outGI = previousFrame;
            return;
        }
        if(iCheckerboardRT==2 && quadIndex(coords)!=framecount%4) {
            outGI = previousFrame;
            return;
        }
#endif

        float3 screenCoords;
        
        float4 mergedGiColor = 0.0;
        float mergedAO = 0.0;
        
        float hits = 0;
        float aoHits = 0;
        
        
    #if !OPTIMIZATION_ONE_LOOP_RT
        int maxRays = iRTMaxRays;
        [loop]
        for(int rays=0;rays<maxRays && maxRays<=iRTMaxRays*OPTIMIZATION_MAX_RETRIES_FAST_MISS_RATIO && (hits==0||mergedGiColor.a<fRTMinRayBrightness);rays++) {
    #else
        int maxRays = 0;
        int rays = 0;
    #endif
            float3 lightVector = normalize(randomTriple(coords+float2(0.0,0.05*rays))-0.5);
            
            RTOUT hitPosition = trace(refWp,lightVector,DRT.x,false);
            if(hitPosition.status == RT_MISSED_FAST) {
                maxRays++;
    #if !OPTIMIZATION_ONE_LOOP_RT
                continue;
    #endif
            }
                
                screenCoords = getScreenPosition(hitPosition.wp);
                
                float3 giColor = 0.0;  
                if(hitPosition.status==RT_HIT_SKY) {
                    giColor = getColor(screenCoords.xy).rgb*fSkyColor;
                } else if(hitPosition.status>=0 ) {
                    
                    giColor = getRayColor(screenCoords.xy).rgb;

                    float3 giColorLch = RGBtoOKLch(giColor);
                    
                    if(bGIMinThickness && hitPosition.DRT.z<(fGIMinThickness*50.0)) {
                        giColorLch.x *= hitPosition.DRT.z/(fGIMinThickness*50.0);
                    }

                    hits+=1.0;

                    // Light hit orientation
                    float orientationSource = dot(lightVector,-refNormal);
                    giColorLch.x *= saturate(0.25+saturate(orientationSource)*4);
                    
                    float3 screenWp = getWorldPosition(screenCoords.xy,getDRT(screenCoords.xy).x);
                    float d = distance(screenWp,refWp);
                    
                    if(giColorLch.x<previousLch.x) {
                        float newL = min(previousLch.x,giColorLch.x*(1.0+d*0.1));
                        if(giColorLch.y>0.1) giColorLch.y = saturate(giColorLch.y+0.075*newL);
                        giColorLch.x = newL;
                        
                    }
                    
                    giColor = OKLchtoRGB(giColorLch);
                      
                    if(d<iAODistance*DRT.x && DRT.x>=fWeaponDepth) {
                        aoHits += 1;
                            
                        float ao = d/(iAODistance*DRT.x);
                        mergedAO += saturate(ao);
                    }
                }
                
                mergedGiColor.rgb = max(giColor,mergedGiColor.rgb);
                mergedGiColor.a = RGBtoOKLab(mergedGiColor.rgb).x;
                
                
                
    #if !OPTIMIZATION_ONE_LOOP_RT
        }
    #endif
    

        if(aoHits<=0) {
            mergedAO = 1.0;
        } else {
            mergedAO /= aoHits;
        }
        
        //mergedGiColor = OKLchtoRGB(mergedGiColor);
        
        float opacity = 1.0/iFrameAccu;
        


        float3 newOK = RGBtoOKLch(mergedGiColor.rgb);
            
        float newB = newOK.x*newOK.y*hits;
        float previousB = (previousLch.x*previousLch.y)*(1.0-opacity);
        
        if(newB+previousB==0) {
            mergedGiColor.rgb = 0;
        } else {
            mergedGiColor.rgb = (newB*mergedGiColor.rgb+previousB*previousFrame.rgb)/(newB+previousB);
        }

        
        opacity = saturate(1.0/iFrameAccu+0.5*hits);
     
        mergedAO = lerp(previousFrame.a,mergedAO,opacity);
        
        outGI = float4(mergedGiColor.rgb,mergedAO);
    }

// SSR
    void PS_SSRLightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!bSSR || fMergingSSR==0.0) {
            outColor = 0.0;
            return;
        }
        
        float3 DRT = getDRT(coords);
        if(DRT.x>fSkyDepth) {
            outColor = 0.0;
        } else {
            
            float3 targetWp = getWorldPosition(coords,DRT.x);            
            float3 targetNormal = getNormal(coords);
            
    
            float3 lightVector = reflect(targetWp,targetNormal)*0.01;
            
            RTOUT hitPosition = trace(targetWp,lightVector,DRT.x,true);
            
            if(hitPosition.status<RT_HIT_SKY) {
                outColor = float4(0.0,0.0,0.0,0.1);
            } else {
                float3 screenPostion = getScreenPosition(hitPosition.wp.xyz);
                float2 previousCoords = getPreviousCoords(screenPostion.xy);
                float3 c = getColorSampler(resultSampler,previousCoords).rgb;
                outColor = float4(c,1.0);
            }
        }
        
            
    }
    
    void fillSSR(
        float2 coords, out float4 outSSR
    ) {
        
    }
    
    void smooth(
        sampler sourceGISampler,
        sampler sourceSSRSampler,
        float2 coords, out float4 outGI, out float4 outSSR,bool firstPass
    ) {
        float3 pixelSize = float3(1.0/tex2Dsize(sourceGISampler),0);
        
        float3 refDRT = getDRT(coords);
        if(refDRT.x>fSkyDepth) {
            outGI = getColor(coords);
            outSSR = float4(0,0,0,1);
            return;
        }
        
        float3 refNormal = getNormal(coords);        
         
        float4 giAo = 0.0;
        float4 ssr = 0.0;
        
        float3 weightSum; // gi, ao, ssr
        
        float2 previousCoords = getPreviousCoords(coords);    
        
        float4 refColor;   
        float3 refColorOKLch;  
        if(firstPass) {
            refColor = getColorSampler(giAccuSampler,previousCoords);
            refColorOKLch = RGBtoOKLch(refColor.rgb);
        }
        
        float4 previousColor = firstPass ? getColorSampler(giAccuSampler,coords) : 0;
        float4 previousSSR = bSSR && firstPass ? getColorSampler(ssrAccuSampler,previousCoords) : 0;

        
        float4 refSSR = getColorSampler(sourceSSRSampler,coords);
        
        float refB = refColorOKLch.x;
        
        float2 currentCoords;
        
        int2 delta;
        
        float bestSSRw = 0;
        float4 ssrCenter = 0;
        float ssrDiff = 0;
        
        
        [loop]
        for(delta.x=-iSmoothRadius;delta.x<=iSmoothRadius;delta.x++) {
            [loop]
            for(delta.y=-iSmoothRadius;delta.y<=iSmoothRadius;delta.y++) {
                
                currentCoords = coords+delta*pixelSize.xy*(firstPass ? iSmoothStep : 1);
                
                float dist = length(delta);
                
                if(dist>iSmoothRadius) continue;
            
                
                float3 DRT = getDRT(currentCoords);
                if(DRT.x>fSkyDepth) continue;
                
                float4 curGiAo = getColorSamplerLod(sourceGISampler,currentCoords,firstPass ? pow(1.0-refB,3)*2 : 0.0);
                
                // Distance weight | gi,ao,ssr 
                float3 weight = 1.0;
                weight.z = safePow(1.0-0.9*dist/iSmoothRadius,iSmoothRadius+1.0);//safePow(1.0+iSmoothRadius/(dist+1),8.0);

                { // AO dist to 0.5
                    float aoMidW = smoothstep(0,1,curGiAo.a);
                    if(curGiAo.a<0.5) aoMidW = 1.0-aoMidW;
                    weight.y += aoMidW*15;
                }
                
                { // GI brightness dist
                    float b = RGBtoOKLab(curGiAo.rgb).x;
                    float d = abs(b-refB);
                    float dw = smoothstep(1,0,d);
                    weight.x += dw*15;
                }
                
                if(firstPass && bGIFastResponse) { // color dist
                    float colorDist = maxOf3(abs(curGiAo.rgb-previousColor.rgb));
                    weight.xy *= 0.5+colorDist*6;
                }
                
                
                
                
                float3 normal = getNormal(currentCoords);
                float3 t = normal-refNormal;
                float dist2 = max(dot(t,t), 0.0);
                float nw = min(exp(-(dist2)/0.5), 1.0);
                
                weight.xyz *= nw*nw;
                
                
                
                { // Depth weight
                    float t = (1.0-refDRT.x)*abs(DRT.x-refDRT.x);
                    float dw = saturate(0.007-t);
                    
                    weight *= dw;
                }
                
#if DX9_MODE
#else
                if(iCheckerboardRT==1 && halfIndex(currentCoords)==framecount%2) {
                    weight *= 4;
                } else if(iCheckerboardRT==2 && quadIndex(currentCoords)==framecount%4) {
                    weight *= 8;
                }
#endif    
                
                giAo.rgb += curGiAo.rgb*weight.x;
                giAo.a += curGiAo.a*weight.y;
                
                
                if(bSSR) {
                    currentCoords = coords+delta*pixelSize.xy;
                    float4 ssrColor = getColorSampler(sourceSSRSampler,currentCoords);
                    
                    ssrColor.rgb *= nw;
                    if(firstPass) ssrColor.rgb *= ssrColor.a<1.0?0.8:1;
                    
                    weight.z *= 0.1+maxOf3(ssrColor.rgb);
                    
                    if(firstPass) {
                        weight.z *= ssrColor.a;
                    }
                    
                    if(firstPass) {
                        float colorDist = 1.0-maxOf3(abs(ssrColor.rgb-previousSSR.rgb));
                        
                        weight.z *= 0.5+colorDist*20;
                        
                        ssrDiff += colorDist*weight.z;
                    }
                    
                    ssr += ssrColor.rgb*weight.z;
                    

                    if(weight.z>bestSSRw) {
                        bestSSRw = weight.z;
                    }

                }
                
                weightSum += weight;
                
                        
            } // end for y
        } // end for x
        
        giAo.rgb /= weightSum.x;
        giAo.a /= weightSum.y;
        
        ssr /=  weightSum.z;
        ssrDiff /= weightSum.z;
        
        if(firstPass) {
            float4 previousPass = getColorSampler(giAccuSampler,previousCoords);
            
            float op = 1.0/iFrameAccu;
            {
                float motionDistance = distance(previousCoords*BUFFER_SIZE,coords*BUFFER_SIZE);
                float colorDist = motionDistance*maxOf3(abs(giAo.rgb-previousPass.rgb));
                op = saturate(op+colorDist*2.5);
            }

            outGI = lerp(previousPass,giAo,op);
            

            if(bSSR) {
                float op = 1.0/iFrameAccu;
                    
                float3 ssrColor;
                
                {
                    float motionDistance = max(0,0.01*(distance(previousCoords*BUFFER_SIZE,coords*BUFFER_SIZE)-1.0));
                    float colorDist = motionDistance*maxOf3(abs(previousSSR.rgb-ssr.rgb));
                    op = saturate(op+colorDist*6);
                }
                
                
                if(bestSSRw>0.0) {
                    ssrColor = lerp(
                        previousSSR.rgb,
                        ssr.rgb,
                        saturate(op*(0.5+weightSum.z*50)*0.25*(1.2-maxOf3(ssr.rgb)))
                    );
                } else {
                    ssrColor = previousSSR.rgb;
                }
                
                outSSR = float4(ssrColor,1.0);
            } else {
                outSSR = 0;
            }
        } else {
            
            outGI = giAo;
            if(bSSR) {
                outSSR = float4(ssr.rgb,1.0);
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

        giBrightness = smoothstep(0,0.5,giBrightness);
        ao = lerp(ao,1.0,saturate(giBrightness*fAoProtectGi));
        
        if(fAOBoostFromGI>0) {
            ao = ao*lerp(1.0,giBrightness,fAOBoostFromGI);
        }
        //ao = fAOMultiplier-(1.0-ao)*fAOMultiplier;
        ao = 1.0-saturate((1.0-ao)*fAOMultiplier);
        
        
        ao = safePow(ao,fAOPow);
        
        ao = saturate(ao);
        ao = lerp(ao,1,saturate(colorBrightness*fAOLightProtect*2.0));
        ao = lerp(ao,1,saturate((1.0-colorBrightness)*fAODarkProtect*2.0));
         
        return saturate(ao);
    }
    
    float3 computeSSR(float2 coords,float brightness) {
        float4 ssr = getColorSampler(ssrAccuSampler,coords);
        if(ssr.a==0) return 0;
        
        float3 ssrOK = RGBtoOKLch(ssr.rgb);
        
        float ssrBrightness = ssrOK.x;
        float ssrChroma = ssrOK.y;
        
        float colorPreservation = lerp(1,safePow(brightness,2),1.0-safePow(1.0-brightness,10));
        
        ssr = lerp(ssr,ssr*0.5,saturate(ssrBrightness-ssrChroma));
        
        float3 DRT = getDRT(coords);
        float roughness = DRT.y;
        
        float rCoef = lerp(1.0,saturate(1.0-roughness*10),fMergingRoughness);
        float coef = fMergingSSR*(1.0-brightness)*rCoef;
        
        return ssr.rgb*coef;
            
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outResult : SV_Target) {
        float3 DRT = getDRT(coords);
        float3 color = getColor(coords).rgb;
        float3 colorOK = RGBtoOKLch(color);
        
        if(DRT.x>fSkyDepth) {
            outResult = float4(color,1.0);
        } else {   
            float originalColorBrightness = colorOK.x;
#if AMBIENT_ON
            if(iRemoveAmbientMode==0 || iRemoveAmbientMode==2) {
                color = filterAmbiantLight(color);
            }
#endif
            
            color = saturate(color*fBaseColor);
            
            
            float4 passColor = getColorSampler(giAccuSampler,coords);
            
            float3 gi = passColor.rgb;
            float3 giOK = RGBtoOKLch(gi);
            float giBrightness =  giOK.x;
            
            color += originalColorBrightness*(1.0-pow(colorOK.y*color.x,0.2))*0.25;
            
            colorOK = RGBtoOKLch(color);
           
            float colorBrightness = colorOK.x;
            
            if(giBrightness>0) { // Apply hue to source color 
            
                float3 newColor = colorBrightness * gi / giBrightness;
                
                float coef = saturate(
                    fGIHueBiais
                    *60.0 // base
                    *abs(0.5-colorOK.y)
                    *(1.0-safePow(originalColorBrightness,0.5)) // color brightness bonus
                     //
                    *(1.0-originalColorBrightness*0.8) // color brightness
                    *(0.5-colorOK.y) // color saturation
                    *(abs(0.8-giBrightness)/0.8) // gi brightness
                    *abs(0.5-giOK.y) // gi saturation
                    *giBrightness
                );
                    
                color = lerp(color,newColor,coef);
            }
            
            
            // Base color
            float3 result = color;
            
            // GI
            
            // Dark areas
            float darkMerging = fGIDarkMerging;
            if(bGIHDR) {
                float avg = getColorOKLch(giSmoothPassSampler,float2(0.5,0.5),9.0).x;
                darkMerging *= 1.0-avg/2.0;
            }
            //float darkBrightnessLevel = saturate(originalColorBrightness);
            float darkB = safePow(1.0-originalColorBrightness,3.0);
            float3 baseDark = saturate(result+0.1);
            
            // 0.13.1 merging
            //result += (lerp(darkBrightnessLevel,result,saturate(colorPureness-giPureness)*5)+0.1)*gi*darkB*darkMerging*4.0;
            // 0.12.0 merging
            result += lerp(0,baseDark*gi ,darkB*darkMerging*4.0); 
        
            
            // Light areas
            float brightB = colorBrightness*safePow(colorBrightness,0.5)*safePow(1.0-colorBrightness,0.75);
            result += lerp(0,gi,brightB*fGILightMerging);
            
            // Mixing
            result = lerp(color,result,fGIFinalMerging);
            
            // Apply AO after GI
            {
                float resultB = RGBtoOKLab(result).x;
                float ao = passColor.a;
                ao = computeAo(ao,resultB,giBrightness);
                result *= ao;
            }
            
            
            outResult = float4(saturate(result),1.0);
            
            
        }
    }
    

    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
    {        
        float3 result = 0;
        
        if(iDebug==DEBUG_OFF) {
            result = getColorSampler(resultSampler,coords).rgb;
            
            float3 resultOK = RGBtoOKLch(result);
            float3 DRT = getDRT(coords);
            float3 color = getColor(coords).rgb;
                
            // SSR
            if(bSSR && fMergingSSR>0.0) {
                float colorBrightness = resultOK.x;
                float3 ssr = computeSSR(coords,colorBrightness);
                result += ssr;
            }
            
            // Levels
            result = (result-iBlackLevel/255.0)/((iWhiteLevel-iBlackLevel)/255.0);
            
            // Distance fading
            if(fDistanceFading<1.0 && DRT.x>fDistanceFading) {
                float diff = DRT.x-fDistanceFading;
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
            float4 passColor =  getColorOKLch(giAccuSampler,coords);
            float giBrightness = passColor.x;
            
            float3 color = getColorOKLch(coords).rgb;
            float colorBrightness = color.x;
            
            float ao = passColor.a;
            ao = computeAo(ao,colorBrightness,giBrightness);
            
            result = ao;
            
        } else if(iDebug==DEBUG_SSR) {
            result = getColorSampler(ssrAccuSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_ROUGHNESS) {
            float3 RT = getColorSampler(RTSampler,coords).xyz;
            //result = RT.x>fSkyDepth?1.0:0.0;
            
            result = RT.x;
        } else if(iDebug==DEBUG_DEPTH) {
            float3 DRT = getDRT(coords);
            result = DRT.x;
            
        } else if(iDebug==DEBUG_NORMAL) {
            result = getColorSampler(normalSampler,coords).rgb;
            
        } else if(iDebug==DEBUG_SKY) {
            float3 RT = getColorSampler(RTSampler,coords).xyz;
            result = RT.x>fSkyDepth?1.0:0.0;
      
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
        } else if(iDebug==DEBUG_THICKNESS) {
            float3 RT = getColorSampler(RTSampler,coords).xyz;
            
            result = RT.y;
      
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT<
        ui_label = "DH_UBER_RT 0.16.7.4-dev";
        ui_tooltip = 
            "_____________ DH_UBER_RT _____________\n"
            "\n"
            " ver 0.16.7.4-dev (2023-12-19)  by AlucardDH\n"
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
        // Normal Roughness
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_RT_save;
            RenderTarget = previousRTTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DRT;
            RenderTarget = RTTex;
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
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_LSPass;
            RenderTarget = lightSourceTex;
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