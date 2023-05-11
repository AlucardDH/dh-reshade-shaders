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

// HIDDEN PERFORMANCE SETTINGS /////////////////////////////////////////////////////////////////
// Should not be modified but can help if you really want to squeeze some FPS at the cost of lower fidelity

// Define is GI rays should be directed to the background:
// it make the GI looks like light is targeting the camera but the gain is less noise
// Default is 1 (slightly biaised), 0 is no biais
#define OPTIMIZATION_BIAISED_RT 0

// Define the maximum distance a ray can travel
// Default is 1.0 : the full screen/depth, less (0.5) can be enough depending on the game
#define OPTIMIZATION_RT_MAX_DISTANCE 1.0

// Define is the motion detection is actived
// Default is 1 (activated), can be deactivated,
// if deactivated : lot of noise and blur when moving, less noise when static
// This could make sence in game with a static camera (point & clicks for example)
#define MOTION_DETECTION 1

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

#define RT_HIT_SKY 0.42
#define RT_MISSED_CROSSED 0.5
#define RT_HIT 1.0
#define RT_MISSED 0.0

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



namespace DH_UBER_RT {

// Textures

    // Common textures

#if TEX_NOISE
    texture blueNoiseTex < source ="dh_rt_noise.png" ; > { Width = 512; Height = 512; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex;  AddressU = REPEAT;  AddressV = REPEAT;  AddressW = REPEAT;};
#endif

#if MOTION_DETECTION
    texture motionTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA16F; };
    sampler motionSampler { Texture = motionTex; };
#endif
    
    texture previousColorTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler previousColorSampler { Texture = previousColorTex; };

    texture previousDepthTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = R8; };
    sampler previousDepthSampler { Texture = previousDepthTex; };

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler resultSampler { Texture = resultTex; };
    
    // RTGI textures
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

    uniform float fDepthHitThreshold <
        ui_type = "slider";
        ui_category = "Common Depth";
        ui_label = "Depth hit threshold";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.010;

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
#if MOTION_DETECTION
    uniform int iMotionRadius <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Motion detection Radius";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
        ui_tooltip = "Define the max distance of motion detection.\n"
                    "Lower=better performance, more noise in motion\n"
                    "Higher=better motion detection, less performance, can producte false detection\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 6;
    
    uniform float fMotionDistanceThreshold <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Motion detection threshold";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define the max difference between 2 frames.";
    > = 0.010;

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
    > = 5;
#else
    uniform int iFrameAccu <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Temporal accumulation";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Define the number of accumulated frames over time.\n"
                    "Lower=less ghosting in motion, more noise\n"
                    "Higher=more ghosting in motion, less noise\n"
                    "/!\\ If motion detection is disable, decrease this to 3 except if you have a very high fps";
    > = 3;
#endif
    uniform float fRayStepPrecision <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Step Precision";
        ui_min = 100.0; ui_max = 4000;
        ui_step = 0.1;
        ui_tooltip = "Define the length of the steps during ray tracing.\n"
                    "Lower=better performance, less quality\n"
                    "Higher=better detection of small geometry, less performances\n"
                    "/!\\ HAS A VARIABLE INPACT ON PERFORMANCES\n"
                    "DEPENDING ON 'Step multiply'";
    > = 2000;
    
    uniform float fRayStepMultiply <
        ui_type = "slider";
        ui_category = "Common RT";
        ui_label = "Step multiply";
        ui_min = 0.01; ui_max = 4.0;
        ui_step = 0.01;
        ui_tooltip = "Define the factor of increase of each step of ray tracing.\n"
                    "Lower=better detection of small geometry, better dectection of far geometry, less performances\n"
                    "Higher=better performance, less quality\n"
                    "/!\\ HAS A BIG INPACT ON PERFORMANCES";
    > = 1.3;
    
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
    
    uniform float fGIBounce <
        ui_type = "slider";
        ui_category = "GI";
        ui_label = "Bounce intensity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define if GI bounces in following frames";
    > = 0.5;

    // AO
    uniform bool bAOAlternative <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Alternative method";
    > = true;
    
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
        ui_tooltip = "Define the intensity of AO";
    > = 3.0;
    
    uniform float fAOPow <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Pow";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
        ui_tooltip = "Define the intensity of the gradient of AO";
    > = 1.0;
    
    uniform int fAODistance <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Distance";
        ui_min = 0; ui_max = 1000;
        ui_step = 0.1;
        ui_tooltip = "Define the range of AO\n"
                    "High values will make the scene darker";
    > = 100;
    
    uniform float fAOLightProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Light protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of bright areas to avoid washed out highlights";
    > = 0.9;
    
    uniform float fAODarkProtect <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Dark protection";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Protection of dark areas to avoid totally black and unplayable parts";
    > = 0.2;
    


    // SSR

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
    
    uniform int iSmoothSSRStep <
        ui_type = "slider";
        ui_category = "Denoising";
        ui_label = "SSR Step";
        ui_min = 1; ui_max = 8;
        ui_step = 1;
        ui_tooltip = "Same as 'Step' but for SSR\n"
                    "Higher:less noise, can smooth surfaces that should not be mixed\n"
                    "This has no impact on performances :)";
    > = 2;
    
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
    > = 1.0;
        
    uniform float fGILightMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Light";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much bright areas are affected by GI.";
    > = 0.5;
    uniform float fGIDarkMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Dark";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much dark areas are affected by GI.";
    > = 0.5;
    
    uniform float fGIFinalMerging <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "GI Final merging";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
        ui_tooltip = "Define how much the whole image is affected by GI.";
    > = 0.5;
    
    uniform float fMergingSSR <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "SSR";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define this intensity of the Screan Space Reflection.";
    > = 0.25;

#if ROUGHNESS
    uniform float fMergingRoughness <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "SSR Roughness";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Define how much the roughness decrease reflection intensity";
    > = 0.6;
#endif

// FUCNTIONS


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
        pxCoords += int2((framecount*random*SQRT2),(framecount*random*PI));
        pxCoords %= size;
        
        return pxCoords.x+pxCoords.y*size.x;
    }

    float randomValue(inout uint seed) {
        seed = seed * 747796405 + 2891336453;
        uint result = 0;
        
#if TEX_NOISE
        result = seed*random;
        return saturate(result/4294967295.0)/PI;
#else
        result = ((seed>>((seed>>28)+4))^seed)*277803737;
        result = (result>>22)^result;
        return result/4294967295.0;
#endif
    }

    float randomNormalDistribution(inout uint seed) {
        float theta = 2*PI*randomValue(seed);
        float rho = sqrt(-2*log(randomValue(seed)));
        return rho*cos(theta);
    }

    float3 randomHemispehreVector(float2 coords) {
#if TEX_NOISE
        int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%512;
        float2 noiseCoords = ((offset+coords*BUFFER_SIZE)%512)/512;
        float3 jitter = normalize(
            getColorSamplerLod(blueNoiseSampler,noiseCoords,0).rgb-0.5-float3(0.25,0,0)
        );
        return normalize(jitter);
#else
        uint seed = getPixelIndex(coords,RENDER_SIZE);
        float3 v = 0;
        v.x = randomNormalDistribution(seed);
        v.y = randomNormalDistribution(seed);
        v.z = randomNormalDistribution(seed);
        return normalize(v) ;
#endif
    }
    
    float3 getRayColor(float2 coords,float2 previousCoords) {
        float3 color = getColor(coords).rgb;
        if(fGIBounce>0.0) {
            float3 previousColor = getColorSampler(giAccuSampler,coords).rgb;
            color = lerp(previousColor*1.5,color,1.0-fGIBounce*0.5);
        }
        return color;
    }

// PS
#if MOTION_DETECTION
    
    float motionDistance(float2 refCoords, float3 refColor,float3 refAltColor,float refDepth, float2 currentCoords) {
        float currentDepth = getColorSampler(previousDepthSampler,currentCoords).x;
        float diffDepth = abs(refDepth-currentDepth);
        
        float3 currentColor = getColorSampler(previousColorSampler,currentCoords).rgb;
        float3 currentAltColor = getColorSampler(previousColorSampler,currentCoords-ReShade::PixelSize).rgb;

        float3 diffColor = abs(currentColor-refColor);
        float3 diffAltColor = abs(currentAltColor-refAltColor);
        
        float dist = distance(refCoords,currentCoords);
        dist += maxOf3(diffColor);
        dist += diffDepth*0.05;
        dist += maxOf3(diffAltColor)*0.6;
        
        return dist;     
    }


    void PS_MotionPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outMotion : SV_Target0) {
        float3 refColor = getColor(coords).rgb;
        float3 refAltColor = getColor(coords-ReShade::PixelSize).rgb;
        float refDepth = ReShade::GetLinearizedDepth(coords);

        int2 delta = 0;
        float deltaStep = 8;
        
        float2 currentCoords = coords;
        float dist = motionDistance(coords,refColor,refAltColor,refDepth,coords);
                
        float bestDist = dist;
        float2 bestMotion = currentCoords;
        
        [loop]     
        for(int radius=1;radius<=iMotionRadius;radius++) {
            deltaStep = 4*radius;
            [loop]
            for(int dx=0;dx<=radius;dx++) {
                
                delta.x = dx;
                delta.y = radius-dx;
                
                currentCoords = coords+ReShade::PixelSize*delta*deltaStep;
                dist = motionDistance(coords,refColor,refAltColor,refDepth,currentCoords);
                if(dist<bestDist) {
                    bestDist = dist;
                    bestMotion = currentCoords;
                }
                
                delta.x = -dx;
                
                currentCoords = coords+ReShade::PixelSize*delta*deltaStep;
                dist = motionDistance(coords,refColor,refAltColor,refDepth,currentCoords);
                if(dist<bestDist) {
                    bestDist = dist;
                    bestMotion = currentCoords;
                }
                
                delta.x = dx;
                delta.y = -(radius-dx);
                
                currentCoords = coords+ReShade::PixelSize*delta*deltaStep;
                dist = motionDistance(coords,refColor,refAltColor,refDepth,currentCoords);
                if(dist<bestDist) {
                    bestDist = dist;
                    bestMotion = currentCoords;
                }
                
                delta.x = -dx;
                
                currentCoords = coords+ReShade::PixelSize*delta*deltaStep;
                dist = motionDistance(coords,refColor,refAltColor,refDepth,currentCoords);
                if(dist<bestDist) {
                    bestDist = dist;
                    bestMotion = currentCoords;
                }
            }
        }
        outMotion = float4(bestMotion,bestDist,1.0);
    }
#endif    
    

#if ROUGHNESS
    void PS_RoughnessPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outRoughness : SV_Target0) {
        if(!bRoughness || fMergingSSR==0.0) discard;
        
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
            float r = maxOf3(diff)/pow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y+ReShade::PixelSize.y*d)).rgb;
            diff = previousY-color;
            r = maxOf3(diff)/pow(d,0.5);
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
            float r = maxOf3(diff)/pow(d,0.5);
            tempA += abs(r);
            tempB = abs(r)>abs(tempB) ? r : tempB;
            previousX = color;
            
            color = getColor(float2(coords.x,coords.y-ReShade::PixelSize.y*d)).rgb;
            diff = previousY-color;
            r = maxOf3(diff)/pow(d,0.5);
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
    
    bool checkHit(float minDepth,float thickness,float rayDepth) {
        return rayDepth>=minDepth && rayDepth<=minDepth+thickness+fDepthHitThreshold;
    }
    
    
    bool crossing(float deltaZbefore, float deltaZ) {
        return (deltaZ<0 && deltaZbefore>0) || (deltaZ>0 && deltaZbefore<0);
    }
    
    float4 trace(float3 refWp,float3 lightVector,float startDepth,bool ssr) {
                
        float stepRatio = 1.001+fRayStepMultiply/10.0;
        float stepLength = 1.0/(ssr?50.0:fRayStepPrecision);
        
        float3 incrementVector = lightVector*stepLength;
        
        float traceDistance = 0;
        float3 currentWp = refWp;

        float deltaZ = 0.0;
        float deltaZbefore = 0.0;

        
        float3 lastSky = 0.5;
        
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
                // wrong direction
                currentWp = refWp-incrementVector;
                incrementVector = reflect(incrementVector,getNormal(getScreenPosition(refWp)));
                
                currentWp = refWp+incrementVector;

                firstStep = false; 
                
            } else if(outScreen) {
                if(lastSky.x!=0.5) {
                    return float4(lastSky,RT_HIT_SKY);
                }
                    
                currentWp -= incrementVector;
                return float4(currentWp, RT_MISSED);
                
            } else if(outSource) {
                    
                if(sign(deltaZ)==sign(deltaZbefore)) {
                    if(deltaZ<0) {
                        distBehind += stepLength;
                    } else {
                        distBehind = 0;
                    }
                }
                
                [loop]
                for(int i=0;i<4 && crossing(deltaZbefore,deltaZ);i++) {
                    ratio = abs(deltaZ/(deltaZbefore-deltaZ));
                    currentWp -= ratio*incrementVector;
                    
                    screenCoords = getScreenPosition(currentWp);
                    depth = ReShade::GetLinearizedDepth(screenCoords.xy);
                   
                    screenWp = getWorldPosition(screenCoords.xy,depth);
                    traceDistance -= ratio*stepLength;
                    deltaZ = screenWp.z-currentWp.z;
                    
                    
                    if(checkHit(depth,distBehind,screenCoords.z)) {
                        return float4(currentWp, RT_HIT);
                    }
                    
                }               
                
            } else {
                outSource = !checkHit(depth,0,screenCoords.z);
            }
            
            firstStep = false;
            
            deltaZbefore = deltaZ;
            
            stepLength *= stepRatio;
            incrementVector *= stepRatio;

        } while(traceDistance<OPTIMIZATION_RT_MAX_DISTANCE*INPUT_WIDTH*2.0*(ssr?1.0:0.001));

        return float4(0,0,0,RT_MISSED);
    }

// GI

    void PS_GILightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0) {
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
            outGI = float4(getColor(coords).rgb,1.0);
            return;
        }
        
        float3 refWp = getWorldPosition(coords,depth);
        float3 normal = getNormal(coords);
        
        float3 previousCoords;
#if MOTION_DETECTION
        previousCoords = getColorSampler(motionSampler,coords).xyz;
#else
        previousCoords = float3(coords,1.0);
#endif

        float4 previousFrame = getColorSampler(giAccuSampler,previousCoords.xy);
        
        float4 hitPosition;
        float3 screenCoords;
        
        float3 mergedGiColor = 0;
        float mergedAO = 1.0;
        
#if !OPTIMIZATION_ONE_LOOP_RT
        [loop]
        for(int rays=0;rays<iRTMaxRays && getBrightness(mergedGiColor)<fRTMinRayBrightness;rays++) {
            float3 randomVector = randomHemispehreVector(coords+0.1*rays);
#else
            float3 randomVector = randomHemispehreVector(coords);
#endif
    
            float3 lightVector = reflect(refWp,randomVector);
            #if OPTIMIZATION_BIAISED_RT>0
                float ratio = (1.0-dot(normal,float3(0,0,1)))/OPTIMIZATION_BIAISED_RT;
                lightVector += float3(0,0,ratio*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE/(2.0-depth));
            #endif
            
            hitPosition = trace(refWp,lightVector,depth,false);
            screenCoords = getScreenPosition(hitPosition.xyz);
            
            float d = distance(hitPosition.xyz,refWp);
                
            float3 giColor;
            if(hitPosition.a>=RT_MISSED_CROSSED) {
                giColor = getRayColor(screenCoords.xy,previousCoords.xy).rgb;
                giColor *= pow(abs(1.0-d/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE),fGIDistancePower);
            } else if(fSkyColor>0 && hitPosition.a==RT_HIT_SKY) {
                giColor = getColor(screenCoords.xy).rgb*fSkyColor;
            } else if(hitPosition.a==RT_MISSED) {
                giColor = previousFrame.rgb;
            }
            
            mergedGiColor = max(giColor,mergedGiColor);         
            
            if(depth>=fWeaponDepth && hitPosition.a>RT_MISSED_CROSSED) {
                float ao = d>fAODistance ? 1.0 : 1.0-pow(saturate(1.0-d/fAODistance),abs(fAOPow));
                mergedAO = min(ao,mergedAO);
            }
#if !OPTIMIZATION_ONE_LOOP_RT
        }
#endif
        
        float previousFrameOpacity = 1.0 - 1.0/iFrameAccu;
        
    #if MOTION_DETECTION
        if(previousCoords.z<=fMotionDistanceThreshold) {
            mergedGiColor = max(mergedGiColor,previousFrame.rgb*previousFrameOpacity);
        }
    #else
        mergedGiColor = max(mergedGiColor,previousFrame.rgb*previousFrameOpacity); 
    #endif
    
        mergedAO = lerp(mergedAO,previousFrame.a,saturate(previousFrameOpacity-abs(0.5-mergedAO)));

        outGI = float4(mergedGiColor,mergedAO);        
    }

// SSR
    void PS_SSRLightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(fMergingSSR==0.0) {
            outColor = float4(0,0,0,1);
            return;
        }
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
            outColor = float4(0,0,0,1);
        } else {
            float opacity = 1.0/iFrameAccu;
        
            float3 targetWp = getWorldPosition(coords,depth);
            float3 targetNormal = getNormal(coords);
    
            float3 lightVector = reflect(targetWp,targetNormal);
            
            float3 normal = getNormal(coords);
            
#if ROUGHNESS
            if(bRoughness) {
                float roughness = getRoughness(coords);
                float randomness = roughness*1000*fRoughnessIntensity;
                
                float3 randomVector = randomHemispehreVector(coords);
                
                lightVector += randomVector*randomness;
            }
#endif
            lightVector = normalize(lightVector);
            
            float4 hitPosition = trace(targetWp,lightVector,depth,true);
#if MOTION_DETECTION
            float3 previousCoords = getColorSampler(motionSampler,coords).xyz;
#else
            float3 previousCoords = float3(coords,1.0);
#endif
            float3 previousSSR = getColorSampler(ssrAccuSampler,previousCoords).rgb;
                    
            if(hitPosition.a==RT_MISSED) {
                // no hit
#if MOTION_DETECTION
                outColor = float4(previousSSR,1);
#else
                outColor = float4(0,0,0,1);
#endif
                
            } else {
                float3 screenCoords = getScreenPosition(hitPosition.xyz);
                float3 color = getColor(screenCoords.xy).rgb;
                float angle = max(0.25,1.0-dot(normal,normalize(float3(coords-0.5,1))));
                color*=angle;
#if MOTION_DETECTION
                color = lerp(color,previousSSR,saturate(0.9-opacity));
                opacity = 1.0;
#endif
                outColor = float4(color,opacity);
            }
        }
    }
    
    void smooth(
        int passNumber,
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
        
        float3 previousCoords;
#if MOTION_DETECTION
        previousCoords = getColorSampler(motionSampler,coords).xyz;
#else
        previousCoords = float3(coords,1.0);
#endif
        
        float4 previousPass = getColorSampler(giAccuSampler,previousCoords.xy);
        
        float3 refNormal = getNormal(coords);
        
         
        float4 giAo = 0;
        float3 ssr;
        float weightSum = 0;
        
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
                float3 ssrColor = getColorSamplerLod(sourceSSRSampler,ssrCurrentCoords, firstPass ? (iSmoothSSRStep-1.0)*0.5 : 0.0).rgb;
                
                // Distance weight | gi,ao,ssr 
                float weight = pow(abs(1.0+iSmoothRadius/(dist+1)),fSmoothDistPow);
                
                
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
                 
                giAo += curGiAo*weight;
                ssr += ssrColor * weight;
                weightSum += weight;
                        
            } // end for y
        } // end for x
        
        giAo /= weightSum;
        ssr /= weightSum;
        
        if(passNumber==1) {
            outGI = lerp(previousPass,giAo,1.0/iFrameAccu);
        } else {
            outGI = giAo;
        }

        outSSR = float4(ssr,1);
        

    }
    
    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {
        smooth(1,giPassSampler,ssrPassSampler,coords,outGI,outSSR, true);
    }
    
    void PS_AccuPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outGI : SV_Target0, out float4 outSSR : SV_Target1) {
        smooth(2,giSmoothPassSampler,ssrSmoothPassSampler,coords,outGI,outSSR, false);
    }
    
    float computeColorPreservationGI(float colorBrightness, float giBrightness) {
        return 1.0;
    }
    
    float computeColorPreservationAO(float colorBrightness, float giBrightness) {
        float colorPreservation = 1.0;
        return colorPreservation;
    } 
    
    float computeAo(float ao,float colorBrightness, float giBrightness) {
        ao = saturate(pow(abs(ao),fAOMultiplier));
        ao = lerp(ao,1.0-(1.0-ao)*(1.0-max(colorBrightness,giBrightness)),fAOLightProtect);
        ao = lerp(ao,1.0-(1.0-ao)*(min(colorBrightness,giBrightness)),fAODarkProtect);
        return ao;
    }
    
    float3 computeSSR(float2 coords,float brightness) {
        float colorPreservation = saturate(pow(abs(brightness*2.0-1.0),10));
            
        float3 ssr = getColorSampler(ssrAccuSampler,coords).rgb;
#if ROUGHNESS
        float roughness = pow(getRoughness(coords),2.0);
#else
        float roughness = 0;
        float fMergingRoughness = 0.001;
#endif
        
        float fixedDark = 1.0-pow(1.0-brightness,fMergingRoughness);
        
        float ssrRatio2 = fixedDark/fMergingRoughness;
        float ssrRatio1 = max(0.0,saturate(1.0-(roughness+0.1))*fMergingRoughness);
        
        return saturate((1.0-saturate(ssrRatio1-ssrRatio2))*ssr*fMergingSSR*(1.0-colorPreservation)*1.5);
            
    }

    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outResult : SV_Target, out float4 outPreviousColor : SV_Target1, out float outDepth : SV_Target2) {
        float depth = ReShade::GetLinearizedDepth(coords);
        float3 color = getColor(coords).rgb;
        
        outPreviousColor = float4(color,1.0);
        outDepth = depth;
        
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
            if(bAOAlternative) ao = lerp(ao,giBrightness,0.5);
            ao = computeAo(ao,colorBrightness,giBrightness);
            color *= ao;
            colorBrightness = getBrightness(color);
            colorPureness = getPureness(color);
            
            // Base color
            float3 result = color;
            
            // GI
            
            // Dark areas
            result += gi*fGIDarkMerging*saturate(fGIDarkMerging-colorBrightness);
            
            // Light areas
            result += (color+0.1)*gi*fGILightMerging;
            
            // Mixing
            float colorPreservation = saturate(pow(abs(colorBrightness*2.0-1.0),10*fGIFinalMerging));
            result = lerp(result,color,colorPreservation);
                
            // SSR
            float3 ssr = computeSSR(coords,colorBrightness);
            result += ssr;
            
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
            float giBrightness = getBrightness(gi);
            
            float3 color = getColor(coords).rgb;
            float colorBrightness = getBrightness(color);
            
            float ao = computeAo(passColor.a,colorBrightness,giBrightness);
            
            result = gi;//*ao;
            
        } else if(iDebug==DEBUG_AO) {
            float4 passColor =  getColorSampler(giAccuSampler,coords);
            float3 gi =  passColor.rgb;
            float giBrightness = getBrightness(gi);
            
            float3 color = getColor(coords).rgb;
            float colorBrightness = getBrightness(color);
            
            float ao = passColor.a;
            if(bAOAlternative) ao = lerp(ao,giBrightness,0.5);
            
            result = computeAo(ao,colorBrightness,giBrightness);
            
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
#if MOTION_DETECTION
            float3  motion = getColorSampler(motionSampler,coords).xyz;
            motion.xy = (motion.xy-coords)*50;
            result = motion;
#endif         
        }
        
        outPixel = float4(result,1.0);
    }


// TEHCNIQUES 
    
    technique DH_UBER_RT {
#if MOTION_DETECTION
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_MotionPass;
            RenderTarget = motionTex;
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
            RenderTarget1 = previousColorTex;
            RenderTarget2 = previousDepthTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }
}