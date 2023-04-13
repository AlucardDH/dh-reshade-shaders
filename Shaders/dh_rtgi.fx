#include "Reshade.fxh"

#ifndef DH_RENDER_SCALE
 #define DH_RENDER_SCALE 0.5
#endif

// Can be used to fix wrong screen resolution
#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT

#define RENDER_WIDTH INPUT_WIDTH*DH_RENDER_SCALE
#define RENDER_HEIGHT INPUT_HEIGHT*DH_RENDER_SCALE

#define RENDER_SIZE int2(RENDER_WIDTH,RENDER_HEIGHT)

#define BUFFER_SIZE int2(INPUT_WIDTH,INPUT_HEIGHT)
#define BUFFER_SIZE3 int3(INPUT_WIDTH,INPUT_HEIGHT,INPUT_WIDTH*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier/1024)
#define NOISE_SIZE 512

#define PI 3.14159265359
#define SQRT2 1.41421356237

#define INV_SQRT_OF_2PI 0.39894228040143267793994605993439  // 1.0/SQRT_OF_2PI
#define INV_PI 0.31830988618379067153776752674503

#define getPeviousDepth(c) tex2D(previousDepthSampler,c)
#define getNormalRaw(c) tex2D(normalSampler,c).xyz
#define getNormal(c) (tex2Dlod(normalSampler,float4(c.xy,0,0)).xyz-0.5)*2
#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4(c.xy,0,l))
#define getColorSampler(s,c) tex2Dlod(s,float4(c.xy,0,0))

#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4(c.xy,0,0))

#define diffT(v1,v2,t) !any(max(abs(v1-v2)-t,0))

namespace DHRTGI {

    texture blueNoiseTex < source ="dh_rt_noise.png" ; > { Width = NOISE_SIZE; Height = NOISE_SIZE; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex;  AddressU = REPEAT;	AddressV = REPEAT;	AddressW = REPEAT;};

    texture normalTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex;};

	texture previousDepthTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = R32F; };
    sampler previousDepthSampler { Texture = previousDepthTex; };

    texture lightPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 4; };
    sampler lightPassSampler { Texture = lightPassTex; MinLOD = 0.0f; MaxLOD = 3.0f;};
    
    texture lightPassHitTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; };
    sampler lightPassHitSampler { Texture = lightPassHitTex; };

    texture lightPassAOTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 4; };
    sampler lightPassAOSampler { Texture = lightPassAOTex; MinLOD = 0.0f; MaxLOD = 3.0f;};

    texture fillGapPass1Tex { Width = RENDER_WIDTH/2; Height = RENDER_HEIGHT/2; Format = RGBA8; MipLevels = 4; };
    sampler fillGapPass1Sampler { Texture = fillGapPass1Tex; MinLOD = 0.0f; MaxLOD = 3.0f;};

    texture fillGapPass2Tex { Width = RENDER_WIDTH/4; Height = RENDER_HEIGHT/4; Format = RGBA8; MipLevels = 4; };
    sampler fillGapPass2Sampler { Texture = fillGapPass2Tex; MinLOD = 0.0f; MaxLOD = 3.0f;};
	
	texture fillGapPass3Tex { Width = RENDER_WIDTH/8; Height = RENDER_HEIGHT/8; Format = RGBA8; MipLevels = 4; };
    sampler fillGapPass3Sampler { Texture = fillGapPass3Tex; MinLOD = 0.0f; MaxLOD = 3.0f;};

	texture smoothPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 4; };
    sampler smoothPassSampler { Texture = smoothPassTex; MinLOD = 0.0f; MaxLOD = 3.0f;};
	
    texture smoothAOPassTex { Width = RENDER_WIDTH; Height = RENDER_HEIGHT; Format = RGBA8; MipLevels = 4; };
    sampler smoothAOPassSampler { Texture = smoothAOPassTex; MinLOD = 0.0f; MaxLOD = 3.0f; };
    
    texture lightAccuTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler lightAccuSampler { Texture = lightAccuTex; };
    
    texture resultTex { Width = INPUT_WIDTH; Height = INPUT_HEIGHT; Format = RGBA8; };
    sampler resultSampler { Texture = resultTex; };

	uniform float frametime < source = "frametime"; >;
    uniform int framecount < source = "framecount"; >;
	uniform int random < source = "random"; min = 0; max = NOISE_SIZE; >;

    uniform bool bDebug <
        ui_category = "Setting";
        ui_label = "Display light only";
    > = false;
    
    uniform float fNormalFilter <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Normal filter";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 1.0;
    
    
    uniform float fPeviousDepth <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "PreviousDepthRecall";
        ui_min = 0.0; ui_max = 0.1;
        ui_step = 0.001;
    > = 0.010;
    
    uniform float fBrightnessOpacity <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Brightness Opacity";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.450;
    
    uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Depth multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.1;
    > = 1.0;

	uniform bool bFrameAccuAuto <
        ui_category = "Setting";
        ui_label = "Temporal accumulation Auto";
    > = true;
    
    uniform int iFrameAccuAutoTarget <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Temporal accumulation Auto target";
        ui_min = 30; ui_max = 1000;
        ui_step = 1;
    > = 60;
    
    uniform int iFrameAccu <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
    > = 3;
    
    uniform float fSkyDepth <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Sky Depth ";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.99;
    
    uniform float fWeaponDepth <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Weapon Depth ";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.001;

// RAY TRACING
    
    uniform float fSubpixelJitter <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Sub pixel jitter";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.1;
    > = 1.0;
    
    uniform int iRayPreciseHit <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Precise hit passes";
        ui_min = 0; ui_max = 8;
        ui_step = 1;
    > = 8;
    
    uniform int iRayPreciseHitSteps <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Precise hit steps";
        ui_min = 2; ui_max = 8;
        ui_step = 1;
    > = 4;


    uniform float fRayStepPrecision <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Step Precision";
        ui_min = 1.0; ui_max = 10000;
        ui_step = 0.1;
    > = 2000;
    
    uniform float fRayStepMultiply <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Step multiply";
        ui_min = 0.01; ui_max = 4.0;
        ui_step = 0.01;
    > = 1.0;

    uniform float fRayHitDepthThreshold <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Ray Hit Depth Threshold";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.350;
    
    uniform bool bLightOmnidirectional <
        ui_category = "Light Omnidirectional";
        ui_label = "Enable";
    > = false;
    
    uniform float fLightOmnidirectionalThres <
        ui_type = "slider";
        ui_category = "Light Omnidirectional";
        ui_label = "Brightness Threshold";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.800;
    
    uniform float fLightOmnidirectionalIntensity <
        ui_type = "slider";
        ui_category = "Light Omnidirectional";
        ui_label = "Intensity/range";
        ui_min = 0.001; ui_max = 5.0;
        ui_step = 0.001;
    > = 1.0;
    
    uniform float fLightOmnidirectionalMinPureness <
        ui_type = "slider";
        ui_category = "Light Omnidirectional";
        ui_label = "Min pureness";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.150;
    
    uniform float fLightOmnidirectionalSaturate <
        ui_type = "slider";
        ui_category = "Light Omnidirectional";
        ui_label = "Saturate";
        ui_min = 0.001; ui_max = 1.0;
        ui_step = 0.001;
    > = 0.150;
    
// LIGHT COLOR
    
    uniform float fSkyColor <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Sky color";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.15;
    
    uniform float fRayBounce <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Bounce strength";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.10;
        
    uniform float fFadePower <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Distance Fading";
        ui_min = 0.0; ui_max = 10;
        ui_step = 0.01;
    > = 1.5;
    
    uniform float fSaturateColor <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Saturate";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.15;
    
    uniform float fSaturateColorPower <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Saturate";
        ui_min = 1.0; ui_max = 10.0;
        ui_step = 0.01;
    > = 1.75;
    
// AO
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
    > = 1.5;
    
    uniform int iAODistance <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Distance";
        ui_min = 0; ui_max = 16;
        ui_step = 1;
    > = 6;
    
    uniform bool bAOProtectLight <
        ui_category = "AO";
        ui_label = "Protect light from AO";
    > = true;
 
    
// SMOTTHING

    uniform bool bDepthWeight <
        ui_category = "Smoothing";
        ui_label = "Depth weight";
    > = true;
    
    uniform bool bNormalWeight <
        ui_category = "Smoothing";
        ui_label = "Normal weight";
    > = true;
    
    uniform bool bPurenessWeight <
        ui_category = "Smoothing";
        ui_label = "Pureness weight";
    > = false;
    
    uniform bool bBrightnessWeight <
        ui_category = "Smoothing";
        ui_label = "Brightness weight";
    > = false;
    
    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Radius";
        ui_min = 0; ui_max = 8;
        ui_step = 1;
    > = 4;

    uniform float fSmoothDepthThreshold <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Depth Threshold";
        ui_min = 0.01; ui_max = 0.2;
        ui_step = 0.01;
    > = 0.02;

    uniform float fSmoothNormalThreshold <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Normal Threshold";
        ui_min = 0; ui_max = 2;
        ui_step = 0.01;
    > = 1.50;
 
// MERGING
    
    uniform float fSourceColor <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Source color";
        ui_min = 0.1; ui_max = 2;
        ui_step = 0.01;
    > = 0.75;
    
    uniform float fPreservePower <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Preserve source power";
        ui_min = 0.1; ui_max = 10.0;
        ui_step = 0.01;
    > = 3.0;
    
    uniform float fLightMult <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.01;
    > = 1.75;
    
    uniform float fLightOffset <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light offset";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.65;
    
    uniform float fLightNormalize <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light normalize";
        ui_min = 0.1; ui_max = 4;
        ui_step = 0.01;
    > = 0.85;
    

    
//////// COLOR SPACE
    float RGBCVtoHUE(in float3 RGB, in float C, in float V) {
        float3 Delta = (V - RGB) / C;
        Delta.rgb -= Delta.brg;
        Delta.rgb += float3(2,4,6);
        Delta.brg = step(V, RGB) * Delta.brg;
        float H;
        H = max(Delta.r, max(Delta.g, Delta.b));
        return frac(H / 6);
    }

    float3 RGBtoHSL(in float3 RGB) {
        float3 HSL = 0;
        float U, V;
        U = -min(RGB.r, min(RGB.g, RGB.b));
        V = max(RGB.r, max(RGB.g, RGB.b));
        HSL.z = ((V - U) * 0.5);
        float C = V + U;
        if (C != 0)
        {
            HSL.x = RGBCVtoHUE(RGB, C, V);
            HSL.y = C / (1 - abs(2 * HSL.z - 1));
        }
        return HSL;
    }
      
    float3 HUEtoRGB(in float H) 
    {
        float R = abs(H * 6 - 3) - 1;
        float G = 2 - abs(H * 6 - 2);
        float B = 2 - abs(H * 6 - 4);
        return saturate(float3(R,G,B));
    }
      
    float3 HSLtoRGB(in float3 HSL)
    {
        float3 RGB = HUEtoRGB(HSL.x);
        float C = (1 - abs(2 * HSL.z - 1)) * HSL.y;
        return (RGB - 0.5) * C + HSL.z;
    }

    float getBrightness(float3 color) {
        return max(max(color.r,color.g),color.b);
    }
    
    float getFrameAccu() {
    	if(bFrameAccuAuto) {
    		float fps = 1000.0/frametime;
    		return max(1,round(fps/iFrameAccuAutoTarget));
    	} else {
    		return iFrameAccu;
    	}
    }
    
    float maxOf3(float3 a) {
		return max(max(a.x,a.y),a.z);
	}
	
	float minOf3(float3 a) {
		return min(min(a.x,a.y),a.z);
	}
	
	float3 max3(float3 a,float3 b) {
		return float3(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z));
	}
	
	float3 min3(float3 a,float3 b) {
		return float3(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z));
	}
    
////// COORDINATES

	float getDepth(float2 coords) {
	
		/*
        float sourceDepth = tex2D(ReShade::DepthBuffer,coords).r;
        
    	if(bLightOmnidirectional && sourceDepth>fRayHitDepthThreshold && isOmniLight(coords)) {
    		outDepth = saturate(float4(sourceDepth/2,0,0,1));
   
    		int2 delta = 0;
    		float maxDist2 = 2;
    		float minDiff = -1;
    		for(delta.x = -1;delta.x<=1;delta.x++) {
    			for(delta.y = -1;delta.y<=1;delta.y++) {
    				float dist = dot(delta,delta);
    				if(dist>maxDist2)continue;
    				float2 deltaCoords = coords + delta*ReShade::PixelSize;
    				if(!inScreen(deltaCoords)) continue;
					if(!isOmniLight(deltaCoords)) {
    					minDiff = minDiff==-1 ? dist : min(minDiff,dist);
    				}
	    		}
    		}
    		if(minDiff==-1) {
    			outDepth = float4(sourceDepth*0.75,0,0,1);
    		} else {
    			outDepth = saturate(float4(sourceDepth*0.75-(minDiff+1)*fLightOmnidirectionalDepthThres/maxDist2,0,0,1));
    			
    		}
    		
		} else {
        	outDepth = float4(sourceDepth,0,0,1);
        }
        */
        
        return ReShade::GetLinearizedDepth(coords);
	}
    
    float2 InputPixelSize() {
    	float2 result = 1.0;
    	return result/float2(INPUT_WIDTH,INPUT_HEIGHT);
    }
    
    float2 RenderPixelSize() {
    	float2 result = 1.0;
    	return result/float2(RENDER_WIDTH,RENDER_HEIGHT);
    }

    bool inScreen(float2 coords) {
        return coords.x>=0 && coords.x<=1
            && coords.y>=0 && coords.y<=1;
    }
    
    bool inScreen(float3 coords) {
        return coords.x>=0 && coords.x<=1
            && coords.y>=0 && coords.y<=1
            && coords.z>=0 && coords.z<=1;
    }

    float3 getWorldPosition(float2 coords) {
        float depth = getDepth(coords);
        float3 result = float3((coords-0.5)*depth,depth);
        result *= BUFFER_SIZE3;
        return result;
    }

    float3 getScreenPosition(float3 wp) {
        float3 result = wp/BUFFER_SIZE3;
        result.xy /= result.z;
        return float3(result.xy+0.5,result.z);
    }
    
    float3 getNormalJitter(float2 coords) {
    
    	int2 offset = int2((framecount*random*SQRT2),(framecount*random*PI))%NOISE_SIZE;
    	float3 jitter = normalize(tex2D(blueNoiseSampler,(offset+coords*BUFFER_SIZE)%(NOISE_SIZE)/(NOISE_SIZE)).rgb-0.5-float3(0.25,0,0));
    	return normalize(jitter);
        
    }
    
    float3 getColorBounce(float2 coords) {
    	float3 result = getColor(coords).rgb;
		if(fRayBounce>0) {
			//result = saturate(result+getColorSampler(smoothPass3Sampler,coords).rgb*fRayBounce);
			result = saturate(result+getColorSampler(resultSampler,coords).rgb*fRayBounce);
		}
		return result;
    }
    
    float3 computeNormal(float2 coords,float3 offset) {
    	float3 posCenter = getWorldPosition(coords);
        float3 posNorth  = getWorldPosition(coords - offset.zy);
        float3 posEast   = getWorldPosition(coords + offset.xz);
        return  normalize(cross(posCenter - posNorth, posCenter - posEast));
    }
    
    bool isOmniLight(float2 coords) {
    	float3 color = tex2Dlod(ReShade::BackBuffer,float4(coords.xy,0,0)).rgb;
		float pureness = maxOf3(color)-minOf3(color);
		
		if(getBrightness(color)>=fLightOmnidirectionalThres && pureness>=fLightOmnidirectionalMinPureness) {
			return true;
		}
		return false;
    }

    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
        
        float3 offset = float3(ReShade::PixelSize, 0.0);
        
        float3 normal = computeNormal(coords,offset);
        if(fNormalFilter>0.0 && fNormalFilter<0.5) {
        	float depth = getDepth(coords);
        	
        	float3 normalTop = computeNormal(coords-offset.zy,offset);
        	float3 normalBottom = computeNormal(coords+offset.zy,offset);
        	if(diffT(normalBottom,normalTop,fNormalFilter)
        	//	&& diffT(normal,normalBottom,fNormalFilter)
			) {
        		float depthTop = getDepth(coords-offset.zy);
        		float depthBottom = getDepth(coords+offset.zy);
        		
        		normal = abs(depth-depthTop)>abs(depth-depthBottom)?normalBottom:normalTop;
        	} else {
	        	float3 normalLeft = computeNormal(coords-offset.xz,offset);
	        	float3 normalRight = computeNormal(coords+offset.xz,offset);
	        	if(diffT(normalLeft,normalLeft,fNormalFilter)
				) {
					float depthLeft = getDepth(coords-offset.xz);
	        		float depthRight = getDepth(coords+offset.xz);
	        		
	        		normal = abs(depth-depthLeft)>abs(depth-depthRight)?normalRight:normalLeft;
        		}
        	}
        }
        if(fNormalFilter>0.5) {
        	float depth = getDepth(coords);
        	
        	float3 normalTop = computeNormal(coords-offset.zy,offset);
        	float3 normalBottom = computeNormal(coords+offset.zy,offset);
        	float3 normalLeft = computeNormal(coords-offset.xz,offset);
	        float3 normalRight = computeNormal(coords+offset.xz,offset);
	        normal += normalTop+normalBottom+normalLeft+normalRight;
	        normal/=5.0;
        }
       	
        outNormal = float4(normal/2.0+0.5,1.0/iFrameAccu);
        
    }
    
    float3 getRayColor(float2 coords) {
    	float3 color = getColorBounce(coords);
			
		if(fSaturateColor>0) {
			float3 hsl = RGBtoHSL(color);
			if(hsl.y>0.1 && hsl.z>0.1) {
				float maxChannel = getBrightness(color.rgb);
				if(maxChannel>0) {
					float3 saturatedColor = pow(color.rgb/maxChannel,fSaturateColorPower);
					color.rgb = fSaturateColor*saturatedColor+(1.0-fSaturateColor)*color.rgb;
				}
			}
		}
		return color;
    }

    float4 trace(float3 refWp,float3 lightVector,float startDepth) {

		float3 startNormal = getNormal(getScreenPosition(refWp));
                
		float stepRatio = 1.0+fRayStepMultiply/10.0;
		
        float stepLength = 1.0/fRayStepPrecision;
        float3 incrementVector = lightVector*stepLength;
        float traceDistance = 0;
        float3 currentWp = refWp;
        
        float rayHitIncrement = 50.0*startDepth*fRayHitDepthThreshold/50.0;
		float rayHitDepthThreshold = rayHitIncrement;

        bool crossed = false;
        float deltaZ = 0;
        float deltaZbefore = 0;
        float3 lastCross;
        
        bool skyed = false;
        float3 lastSky;
		
		bool outSource = false;
        bool firstStep = true;
        
        bool startWeapon = startDepth<fWeaponDepth;
        float weaponLimit = fWeaponDepth*BUFFER_SIZE3.z;
		
		
        do {
        	currentWp += incrementVector;
            traceDistance += stepLength;
            
            float3 screenCoords = getScreenPosition(currentWp);
			
			bool outScreen = !inScreen(screenCoords) && (!startWeapon || currentWp.z<weaponLimit);
            
            float3 screenWp = getWorldPosition(screenCoords.xy);
            
            deltaZ = screenWp.z-currentWp.z;
            
            float depth = getDepth(screenCoords.xy);
            bool isSky = depth>fSkyDepth;
            if(isSky) {
            	skyed = true;
            	lastSky = currentWp;
            }
            
            
            if(firstStep && deltaZ<0) {
				// wrong direction
                currentWp = refWp-incrementVector;
                incrementVector = reflect(incrementVector,startNormal);
                
                currentWp = refWp+incrementVector;
                //traceDistance = 0;

                firstStep = false; 
            } else if(outSource) {
           
				if(bLightOmnidirectional) {
            		// TODO
            		if(isOmniLight(screenCoords.xy)) {
            			return float4(currentWp,0.5);
            		}
				} 
				
            	
            	if(!outScreen && sign(deltaZ)!=sign(deltaZbefore)) {
            		// search more precise
            		float preciseRatio = 1.0/iRayPreciseHitSteps;
            		float3 preciseIncrementVector = incrementVector;
            		float preciseLength = stepLength;
            		for(int precisePass=0;precisePass<iRayPreciseHit;precisePass++) {
            			preciseIncrementVector *= preciseRatio;
						preciseLength *= preciseRatio;
						
						int preciseStep=0;
            			bool recrossed=false;
            			while(!recrossed && preciseStep<iRayPreciseHitSteps-1) {
            				currentWp -= preciseIncrementVector;
            				traceDistance -= preciseLength;
            				deltaZ = screenWp.z-currentWp.z;
            				recrossed = sign(deltaZ)==sign(deltaZbefore);
                            preciseStep++;
            			}
            			if(recrossed) {
            				currentWp += preciseIncrementVector;
            				traceDistance += preciseLength;
            				deltaZ = screenWp.z-currentWp.z;
            			}
            		}
            		
            		lastCross = currentWp;
            		crossed = true;
            		
            		
            	}
            	if(outScreen) {
            		if(crossed) {
            			return float4(lastCross,0.5);
            		}
            		if(skyed) {
            			return float4(lastSky,fSkyColor);
            		}
            		return float4(currentWp, 0.01); // TODO HERE
            	} 
				if(abs(deltaZ)<=rayHitDepthThreshold) {
            		// hit !
            		return float4(crossed ? lastCross : currentWp, 1.0);
            	}
            } else {
            	if(outScreen) {
            		if(crossed) {
            			return float4(lastCross,0.5);
            		}
            		if(skyed) {
            			return float4(lastSky,fSkyColor);
            		}
            		currentWp -= incrementVector;
            		//screenCoords = getScreenPosition(currentWp);
            				
            		//if(screenCoords.z>fSkyDepth) {
            		//	return float4(currentWp,1.0);
            		return float4(currentWp,0.01);
				}
				outSource = deltaZ>rayHitDepthThreshold;
            	if(!outSource) {
            		float3 normal = getNormal(screenCoords);
            	//	outSource = diffT(normal,startNormal,0.1);
            	}
            }

            firstStep = false;
            
            deltaZbefore = deltaZ;
            
            stepLength *= stepRatio;
            if(rayHitDepthThreshold<fRayHitDepthThreshold) rayHitDepthThreshold +=rayHitIncrement;
            incrementVector *= stepRatio;

        } while(traceDistance<INPUT_WIDTH);

        return 0.0;

    }

    void PS_LightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outHit : SV_Target1, out float4 outDistance : SV_Target2) {
        
        float depth = ReShade::GetLinearizedDepth(coords);
        if(depth>fSkyDepth) {
			outDistance = float4(1,0,0,1);
			return;
		}
		
		if(fSubpixelJitter>0.0) {
        	float2 jitter = float2(random%16,(random+8)%16)/16.0;
        	float2 jitterCoords = coords + ReShade::PixelSize*fSubpixelJitter*(-0.5+jitter);
        	float jitterDepth = ReShade::GetLinearizedDepth(jitterCoords);
        	if(abs(depth-jitterDepth)<fSmoothDepthThreshold) {
        		coords = jitterCoords;
        		depth = jitterDepth;        		
        	}
        }
		
        float3 targetWp = getWorldPosition(coords);
        float3 targetNormal = getNormalJitter(coords);
        //float3 targetNormal = getNormalJitter2(coords,targetWp);

        float3 lightVector = reflect(targetWp,targetNormal);
        
        float opacity = 1.0;
        float aoOpacity = 1.0;
	        
        
       // float4 hitColor = trace(targetWp,lightVector);
        float4 hitPosition = trace(targetWp,lightVector,depth);
        float3 screenCoords = getScreenPosition(hitPosition.xyz);
        
        if(hitPosition.a<=0.1) {
        	// no hit
        	outColor = 0.0;
	  	  outHit = float4(screenCoords,0.0);	
            outDistance = float4(1,0,0,0.5);
            return;
        }
        
        
        float3 color = getRayColor(screenCoords.xy);
        
    	float b = getBrightness(color);
    	
    	float d = abs(distance(hitPosition.xyz,targetWp));
                    
    	float distance = 1.0+0.02*d;
    	//float distanceRatio = 0.1+1.0/pow(distance,0.05*fFadePower);//(1-pow(distance,fFadePower)/pow(iRayDistance,fFadePower));
        float distanceRatio = 0.0+1.0/pow(distance,fFadePower);//(1-pow(distance,fFadePower)/pow(iRayDistance,fFadePower));
        
        float previousDepth = getPeviousDepth(coords).r;
  
        if(bLightOmnidirectional && isOmniLight(screenCoords.xy)) {
        	d = iAODistance;
	        if(fLightOmnidirectionalSaturate>0) {
        		float3 hsl = RGBtoHSL(color);
        		hsl.y = 1.0;
	        	hsl.z = 0.5;
	        	float3 saturated = HSLtoRGB(hsl);
	        	color = saturate(fLightOmnidirectionalSaturate*saturated+color*(1.0-fLightOmnidirectionalSaturate)*fLightOmnidirectionalIntensity);
        	}
		} 
		if(fBrightnessOpacity>0) {
        	opacity *= (1.0-fBrightnessOpacity)+fBrightnessOpacity*b;
        }

		//outColor = saturate(float4(distanceRatio*color,hitPosition.a*opacity));
  	    outHit = float4(screenCoords,hitPosition.a<1.0 ? 1 : 0);	
  	    outColor = saturate(float4(color,distanceRatio*hitPosition.a*hitPosition.a));
  	    if(hitPosition.a>=1.0) {
  	      
	  	  if(screenCoords.z>=0.9) {
	  	  	outDistance = float4(iAODistance>0?0:1,0,0,aoOpacity);
	  	  } else {
	  	  	if(d>iAODistance) {
	  	  		outDistance = float4(1,0,0,0.5*aoOpacity);
	  	  	} else {
	  	  		outDistance = float4(d/iAODistance,0,0,aoOpacity*(1.0-d/iAODistance));
	  	  	}
	  	  	
	  	  }
  	    } else {
  	    	//outColor = float4(0,0,0,0.5);
  	  	  if(d>iAODistance) {
	  	  		outDistance = float4(1,0,0,0.5*aoOpacity);
	  	  	} else {
	  	  		outDistance = float4(d/iAODistance,0,0,0.5*aoOpacity);
	  	  	}
  	    }
    }


	void addIfMatchDepth(in out float4 result,sampler sourceSampler,sampler previousLowerSampler, float2 coords, float refDepth) {
		float depth = getDepth(coords);
		if(abs(depth-refDepth)<=0.1) {
			float4 color = getColorSampler(sourceSampler,coords);
			if(color.a<0.1) {
				float4 previous = getColorSampler(previousLowerSampler,coords);
				float previousB = getBrightness(previous.rgb);
				color += previous*previousB;
				color /= 1.0+previousB;
			}
			color.rgb *= color.a;
			result += color;
		}
	}
	
    void PS_FillGapPass(sampler sourceSampler,sampler previousLowerSampler,float2 pixelSize, float2 coords : TexCoord, out float4 outColor : SV_Target0,float opacity) {
    	float refDepth = getDepth(coords);
        float3 pixelSizeZ = float3(pixelSize,0);
        
        float4 result = 0;
        float bWeight = 0;
        addIfMatchDepth(result,sourceSampler,previousLowerSampler,coords,refDepth);
        addIfMatchDepth(result,sourceSampler,previousLowerSampler,coords+pixelSizeZ.xz,refDepth);
        addIfMatchDepth(result,sourceSampler,previousLowerSampler,coords+pixelSizeZ.zy,refDepth);
        addIfMatchDepth(result,sourceSampler,previousLowerSampler,coords+pixelSizeZ.xy,refDepth);

		float confidence = result.a;
		
        if(confidence==0) {
            result = 0;
        } else {
            result.rgb /= result.a;
            //result.a = saturate(confidence/4.0);
        }
        
        result.a *= opacity;

        outColor = saturate(result);
    }
    
    void PS_FillGapPass1(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
    	PS_FillGapPass(lightPassSampler,fillGapPass1Sampler,RenderPixelSize(),coords,outColor,1.0);
    }
    
    void PS_FillGapPass2(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
    	PS_FillGapPass(fillGapPass1Sampler,fillGapPass2Sampler,RenderPixelSize()*2.0,coords,outColor, 1.0);
    }
    
    void PS_FillGapPass3(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
    	PS_FillGapPass(fillGapPass2Sampler,smoothPassSampler,RenderPixelSize()*4.0,coords,outColor, 1.0/getFrameAccu());
    }
    
    float4 getColorWithFallback(float2 coords) {
    	float4 color = getColorSampler(lightPassSampler,coords);
    	
    	float4 colorFB1 = getColorSampler(fillGapPass1Sampler,coords);
    	float4 colorFB2 = getColorSampler(fillGapPass2Sampler,coords);
    	float4 colorFB3 = getColorSampler(fillGapPass3Sampler,coords);
    	float4 defaultColor = float4(0,0,0,1);
    	
    	bool bReconDebug = true;
    	if(false) {
    		color.rgb = float3(1,1,1);
    		colorFB1.rgb = color.rgb*0.75;
    		colorFB2.rgb = color.rgb*0.5;
    		colorFB3.rgb = color.rgb*0.25;
	    	defaultColor = float4(0,0,0,1);
		}
		
		
		
		if(color.a>0.1) {
			return color;
		}
		if(colorFB1.a>0.1) {
			return colorFB1;
		}
		if(colorFB2.a>0.1) {
			return colorFB2;
		}
		if(colorFB3.a>0.1) {
			return colorFB3;
		}
		return defaultColor;
		
    }

    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outAO : SV_Target1) {
    	float refDepth = getDepth(coords);
		if(refDepth>fSkyDepth) {
    		outColor = 1.0;
    		outAO = 1.0;
    		return;
    	}
		
		float opacity = 1.0/getFrameAccu();
		
		if(iSmoothRadius==0) {
    		outColor = float4(getColorWithFallback(coords).rgb,opacity);
    		float ao = getColorSampler(lightPassAOSampler,coords).r;
    		outAO = float4(ao,ao,ao,opacity);
    		return;
    	}
    	
    	int2 coordsInt = coords*RENDER_SIZE;
    	
        float3 refNormal = getNormal(coords);
        
        float3 result = 0;
        float weightSum = 0;
        
        int foundSamples = 0;
		
        float ao = 0;
        float aoWeightSum = 0;
        
        float2 pixelSize = RenderPixelSize();
        
        float2 minCoords = saturate(coords-iSmoothRadius*pixelSize);
        float2 maxCoords = saturate(coords+iSmoothRadius*pixelSize);
        float2 currentCoords = minCoords;
        
        
        for(currentCoords.x=minCoords.x;currentCoords.x<=maxCoords.x;currentCoords.x+=pixelSize.x) {
        	for(currentCoords.y=minCoords.y;currentCoords.y<=maxCoords.y;currentCoords.y+=pixelSize.y) {
        		int2 currentCoordsInt = currentCoords*RENDER_SIZE;
        		float dist2 = distance(coordsInt,currentCoordsInt);
        		
        		if(dist2>iSmoothRadius) continue;
        	
	        	
                float depth = getDepth(currentCoords);
                if(depth>fSkyDepth) continue;
                
                if(abs(depth-refDepth)<=fSmoothDepthThreshold) {
                	
                    float3 normal = getNormal(currentCoords);
                    if(diffT(normal,refNormal,fSmoothNormalThreshold)) {
                    	
	                    
						//float3 hitPos = tex2Dfetch(lightPassHitSampler,currentCoordsInt).xyz;
						
                		float4 color = getColorWithFallback(currentCoords);
               		
                    	float aoWeight = color.a;
                        float weight = color.a;
                        
                        float distWeight = iSmoothRadius/(dist2+1);
                        weight *= distWeight;
                        aoWeight *= distWeight;
                    	if(bPurenessWeight) {
                    		float pureness = maxOf3(color.rgb)-minOf3(color.rgb);
                    		weight += pureness*10;
                    	}
                    	if(bBrightnessWeight) {
                    		float brightness = getBrightness(color.rgb);
                    		weight *= brightness*10;
                    	}
                    	if(bNormalWeight) {
                    		float nw = abs(dot(normal,refNormal));
                    		weight *= nw;
                    		aoWeight *= nw;
                    	}
                    	if(bDepthWeight) {
                    		float dw = 1.0-abs(depth-refDepth)/fSmoothDepthThreshold;
                    		weight *= dw*dw;
                    		aoWeight *= dw*dw;
                    	}
                        
						// hit
						float4 aoColor = getColorSampler(lightPassAOSampler,currentCoords);
						ao += aoColor.r*aoWeight;
						aoWeightSum += aoWeight;
						
                    	result += color.rgb*weight;
                        weightSum += weight;
                        foundSamples++;

                    } // end normal
                } // end depth  
            } // end for y
        } // end for x

		float resultAO = ao/aoWeightSum;
        //outAO = float4(resultAO,resultAO,resultAO,resultAO<1.0 ? 1.0-resultAO : 1.0);
        
        
        if(foundSamples<1) {
        	// not enough
        	result = getColorSampler(lightPassSampler,coords).rgb;
        	resultAO = 1.0;
        } 
        
        //result = float(foundSamples)/10;//saturate(fLightMult*result/weightSum);
		//result = saturate(fLightMult*result/weightSum);
		result /= weightSum;
        outColor = float4(result,opacity);
        outAO = float4(resultAO,resultAO,resultAO,opacity);
    }
	
	float3 minSum3(float3 a,float b) {
		float s = a.x+a.y+a.z;
		return s>0 && s>b ? b*a/s : a;
	}
	
	void PS_AccuPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
		float previousDepth = getPeviousDepth(coords).r;
		float depth = ReShade::GetLinearizedDepth(coords);
		
		float opacity = 1.0/getFrameAccu();
		
		float3 color = tex2D(smoothPassSampler,coords).rgb;
		
		float brightness = getBrightness(color);
		if(fBrightnessOpacity>0) {
        	opacity *= (1.0-fBrightnessOpacity)+fBrightnessOpacity*brightness;
        }
		
        if(abs(previousDepth-depth)>fPeviousDepth) {
        	opacity = 1.0;
        }
		outColor = float4(color,opacity);
	}
	
    
    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target,out float4 outDepth : SV_Target1)
    {
        float3 color = getColor(coords).rgb;
        float depth = getDepth(coords);
        if(depth>fSkyDepth) {
        	outPixel = float4(color,1.0);
		} else {

			float3 colorHsl = RGBtoHSL(color);
	        float3 light = getColorSampler(lightAccuSampler,coords).rgb;
	        float3 lightHsl = RGBtoHSL(light);
	        
	        float b = getBrightness(color);
	        float lb = getBrightness(light);
	        
	        float ao = max(getColorSampler(smoothAOPassSampler,coords).r,b);
	        
	       	
	   	float3 surfaceHsl = RGBtoHSL(color);
	   	surfaceHsl.y = 0.0;
	   	surfaceHsl.z = 0.5;
	   	float3 surface = b*0.5;
	   	
	   	float3 result = 0;
	   	result = (
				fLightMult*light*(color+fLightOffset)
				+fSourceColor*color
		   )/(0.9+fLightNormalize);
		   
			float correctedAo = pow(ao,fAOMultiplier*(depth<=fWeaponDepth ? 0.2 : 1.0));
	    	if(bAOProtectLight) {
	    		correctedAo = lb+correctedAo*(1.0-lb);
	    	}
	    	
	   	result *= correctedAo;
			
	   	float preserveWhite = pow(b,fPreservePower);
	   	float preserveDark = pow(1.0-b,fPreservePower);
	   	float preserveUnsaturated = 0;//pow(1.0-colorHsl.y,fPreservePower);
	   	float preserve = max(max(preserveUnsaturated,preserveWhite),preserveDark);
	   	
	   	
	   	
	   	outPixel = float4(saturate(preserve*color+(1.0-preserve)*result),1.0);
       }
       outDepth = float4(depth,0,0,1);
    }
    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
    	float4 color = getColorSampler(resultSampler,coords);
    	
    	if(bDebug) {
    		float b = getBrightness(color.rgb);
        	float ao = getColorSampler(smoothAOPassSampler,coords).r;
        	float4 light = getColorSampler(lightAccuSampler,coords);
        	float lb = getBrightness(light.rgb);
        	
        	float depth = getDepth(coords);
        	float correctedAo = pow(ao,fAOMultiplier*(depth<=fWeaponDepth ? 0.2 : 1.0));
    		if(bAOProtectLight) {
        		correctedAo = lb+correctedAo*(1.0-lb);
        	}
    		color = correctedAo * light;
    		color.a = 1;
    	}
    	/*
    	if(bDebug) {
    		color = getColorSampler(lightPassAOSampler,coords);
    		color.a = 1;
    	}
    	*/
    	
        outPixel = color;
    }
    
    
    technique DH_RTGI {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_NormalPass;
            RenderTarget = normalTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_LightPass;
            RenderTarget = lightPassTex;
            RenderTarget1 = lightPassHitTex;
            RenderTarget2 = lightPassAOTex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_FillGapPass1;
            RenderTarget = fillGapPass1Tex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_FillGapPass2;
            RenderTarget = fillGapPass2Tex;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_FillGapPass3;
            RenderTarget = fillGapPass3Tex;
            
            ClearRenderTargets = true;
            
            BlendEnable = true;
			BlendOp = ADD;

			// The data source and optional pre-blend operation used for blending.
			// Available values:
			//   ZERO, ONE,
			//   SRCCOLOR, SRCALPHA, INVSRCCOLOR, INVSRCALPHA
			//   DESTCOLOR, DESTALPHA, INVDESTCOLOR, INVDESTALPHA
			SrcBlend = SRCALPHA;
			SrcBlendAlpha = ONE;
			DestBlend = INVSRCALPHA;
			DestBlendAlpha = ONE;
        }
		pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothPass;
            RenderTarget = smoothPassTex;
            RenderTarget1 = smoothAOPassTex;
            
            ClearRenderTargets = false;
            
            BlendEnable = true;
			BlendOp = ADD;

			// The data source and optional pre-blend operation used for blending.
			// Available values:
			//   ZERO, ONE,
			//   SRCCOLOR, SRCALPHA, INVSRCCOLOR, INVSRCALPHA
			//   DESTCOLOR, DESTALPHA, INVDESTCOLOR, INVDESTALPHA
			SrcBlend = SRCALPHA;
			SrcBlendAlpha = ONE;
			DestBlend = INVSRCALPHA;
			DestBlendAlpha = ONE;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_AccuPass;
            RenderTarget = lightAccuTex;

            ClearRenderTargets = false;
            
            BlendEnable = true;
			BlendOp = ADD;

			// The data source and optional pre-blend operation used for blending.
			// Available values:
			//   ZERO, ONE,
			//   SRCCOLOR, SRCALPHA, INVSRCCOLOR, INVSRCALPHA
			//   DESTCOLOR, DESTALPHA, INVDESTCOLOR, INVDESTALPHA
			SrcBlend = SRCALPHA;
			SrcBlendAlpha = ONE;
			DestBlend = INVSRCALPHA;
			DestBlendAlpha = ONE;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateResult;
            RenderTarget = resultTex;
            RenderTarget1 = previousDepthTex;

            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }


}