#include "Reshade.fxh"

#define RES_SCALE 2
#define RES_WIDTH (BUFFER_WIDTH/RES_SCALE)
#define RES_HEIGHT (BUFFER_HEIGHT/RES_SCALE)

#define BUFFER_SIZE int2(RES_WIDTH,RES_HEIGHT)
#define BUFFER_SIZE3 int3(RES_WIDTH,RES_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier/RES_SCALE)
#define NOISE_SIZE 32

#define PI 3.14159265359
#define SQRT2 1.41421356237

#define getDepth(c) ReShade::GetLinearizedDepth(c)
#define getNormal(c) (tex2Dlod(normalSampler,float4(c,0,0)).xyz-0.5)*2
#define getColorSampler(s,c) tex2Dlod(s,float4(c,0,0))
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4(c,0,0))

#define diffT(v1,v2,t) !any(max(abs(v1-v2)-t,0))

namespace DH2 {

    texture blueNoiseTex < source ="LDR_RGBA_0.png" ; > { Width = NOISE_SIZE; Height = NOISE_SIZE; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex; };

    texture normalTex { Width = RES_WIDTH; Height = RES_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex; };

    texture lightPassTex { Width = RES_WIDTH; Height = RES_HEIGHT; Format = RGBA8; };
    sampler lightPassSampler { Texture = lightPassTex; };
    
    texture lightAccuTex { Width = RES_WIDTH; Height = RES_HEIGHT; Format = RGBA8; };
    sampler lightAccuSampler { Texture = lightAccuTex; };

	texture smoothPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothPassSampler { Texture = smoothPassTex; };

	texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler resultSampler { Texture = resultTex; };

    uniform int framecount < source = "framecount"; >;
	
    uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Depth multiplier";
        ui_min = 0.1; ui_max = 100;
        ui_step = 0.1;
    > = 0.5;

    uniform int iFrameAccu <
        ui_type = "slider";
        ui_category = "Samples";
        ui_label = "Frame accu";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
    > = 2;
    
    uniform float fRayBounce <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Bounces";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.1;
    > = 0.2;

    uniform bool bRayUntilHit <
        ui_category = "Ray tracing";
        ui_label = "Search until hit";
    > = false;
    
    uniform bool bRayOutScreenHit <
        ui_category = "Ray tracing";
        ui_label = "Out screen hit";
    > = false;
    
    uniform bool bRayOutSearchHit <
        ui_category = "Ray tracing";
        ui_label = "Out search hit";
    > = true;
    
    uniform float fOutRatio <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Out hit ratio";
        ui_min = 0.1; ui_max = 1;
        ui_step = 0.01;
    > = 1.0;
    
    uniform int iRayDistance <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Search Distance";
        ui_min = 1; ui_max = BUFFER_WIDTH;
        ui_step = 1;
    > = 240;
    
    uniform float fFadePower <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Fade power";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.1;
    > = 1;

    uniform float fRayPrecision <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Precision";
        ui_min = 0.1; ui_max = 20.0;
        ui_step = 0.1;
    > = 1.0;

    uniform float fRayHitDepthThreshold <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Ray Hit Depth Threshold";
        ui_min = 0.01; ui_max = 10;
        ui_step = 0.01;
    > = 0.03;
  
    
    uniform float fJitter <
        ui_type = "slider";
        ui_category = "Ray tracing";
        ui_label = "Jitter";
        ui_min = -1.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.01;

    uniform int iSmoothRadius <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Radius";
        ui_min = 0; ui_max = 16;
        ui_step = 1;
    > = 4;

    uniform float fSmoothDepthThreshold <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Depth Threshold";
        ui_min = 0; ui_max = 0.2;
        ui_step = 0.01;
    > = 0.02;

    uniform float fSmoothNormalThreshold <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Normal Threshold";
        ui_min = 0; ui_max = 2;
        ui_step = 0.01;
    > = 0.5;
    
    uniform float fSourceColor <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Source color";
        ui_min = 0.1; ui_max = 2;
        ui_step = 0.01;
    > = 1.0;
    
    uniform float fLightMult <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.01;
    > = 1.35;
    
    uniform bool bDebug = false;

    float2 PixelSize() {
        return ReShade::PixelSize*RES_SCALE;
    }

    float getBrightness(float3 color) {
        return max(max(color.r,color.g),color.b);
    }

    int2 toPixels(float2 coords) {
        return BUFFER_SIZE*coords;
    }

    bool inScreen(float2 coords) {
        return coords.x>=0 && coords.x<=1
            && coords.y>=0 && coords.y<=1;
    }

    bool isPixelTreated(float2 coords) {
        float2 noiseCoords = float2(toPixels(coords)%NOISE_SIZE)/NOISE_SIZE;
        float4 noise = getColorSampler(blueNoiseSampler,noiseCoords);
        float v = noise.x;
        int accuIndex = framecount % iFrameAccu;
        float accuWidth = 1.0/(iFrameAccu);
        float accuStart = accuIndex*accuWidth;

        return accuStart<=v && v<accuStart+accuWidth;
    }

    float3 getWorldPosition(float2 coords) {
        float depth = getDepth(coords);
        float3 result = float3((coords-0.5)*depth,depth);
        result *= BUFFER_SIZE3;
        return result;
    }

    float2 getScreenPosition(float3 wp) {
        float3 result = wp/BUFFER_SIZE3;
        result /= result.z;
        return result.xy+0.5;
    }

    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
        float3 offset = float3(PixelSize().xy, 0.0);

        float3 posCenter = getWorldPosition(coords);
        float3 posNorth  = getWorldPosition(coords - offset.zy);
        float3 posEast   = getWorldPosition(coords + offset.xz);
        float3 normal = normalize(cross(posCenter - posNorth, posCenter - posEast));
        
        outNormal = float4(normal/2.0+0.5,1.0);
    }
    
    float4 getRayColor(float2 coords) {
    	return fRayBounce>0 
			? fRayBounce*getColorSampler(resultSampler,coords)+(1-fRayBounce)*getColor(coords)
			: getColor(coords);
    }

    float4 trace(float3 refWp,float3 lightVector) {


        float stepLength = 1.0/fRayPrecision;
        float3 incrementVector = lightVector*stepLength;
        float traceDistance = 0;
        float3 currentWp = refWp;
        
        bool crossed = false;
        float deltaZ = 0;
        float deltaZbefore = 0;
        float4 lastCross;
		
		bool outSource = false;
		
        do {
        	currentWp += incrementVector;
            traceDistance += stepLength;
            
            float2 screenCoords = getScreenPosition(currentWp);
            
			bool outSearch = !bRayUntilHit && traceDistance>=iRayDistance;
			if(outSearch && !bRayOutSearchHit) return float4(0,0,0,1);
            
			bool outScreen = !inScreen(screenCoords);
			float3 screenWp = getWorldPosition(screenCoords);
            if(!outScreen) outScreen = currentWp.z<0 || (currentWp.z>RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier);
            if(outScreen && !bRayOutScreenHit) return float4(0,0,0,1);
            
            deltaZ = screenWp.z-currentWp.z;
            
            float distanceRatio = (1-pow(traceDistance,fFadePower)/pow(iRayDistance,fFadePower));
            	
			if(outSource) {
            	if(sign(deltaZ)!=sign(deltaZbefore)) {
            		lastCross = distanceRatio*getRayColor(screenCoords);
            		crossed = true;
            	}
            	if(abs(deltaZ)<=fRayHitDepthThreshold || outScreen || outSearch) {
            		// hit !
            		float4 color = crossed ? lastCross : distanceRatio*getRayColor(screenCoords);
            		float b = getBrightness(color.rgb);
	                return distanceRatio*(0.5+b)*(outScreen || outSearch ? fOutRatio : 1)*color;
            	}
            } else {
            	if(outScreen) {
					if(bRayOutScreenHit) {
						float4 color = crossed ? lastCross : distanceRatio*getRayColor(screenCoords);
            			float b = getBrightness(color.rgb);
	                	return distanceRatio*(0.5+b)*fOutRatio*color;
					} else {
						return float4(0,0,0,1);
					}
				}
            	outSource = abs(deltaZ)>fRayHitDepthThreshold;
            }
            
            deltaZbefore = deltaZ;

        } while(bRayUntilHit || traceDistance<iRayDistance);

        return float4(0,0,0,1);

    }
    
    void PS_ClearAccu(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        if(framecount%iFrameAccu!=0) discard;
        outPixel = float4(0,0,0,1);
    }

    void PS_LightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        if(!isPixelTreated(coords)) {
            return;
        }

        float3 targetWp = getWorldPosition(coords);
        float3 targetNormal = getNormal(coords);

        float3 lightVector = reflect(targetWp,targetNormal);
        
        float3 jitter = tex2Dfetch(blueNoiseSampler,(framecount+coords*BUFFER_SIZE)%NOISE_SIZE).rgb;
        lightVector += jitter*fJitter;
        lightVector = normalize(lightVector);
        float4 hitColor = trace(targetWp,lightVector);
         
        outColor = hitColor;
    }
    
    void PS_UpdateAccu(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        if(framecount%iFrameAccu!=iFrameAccu-1) discard;
        outPixel = getColorSampler(lightPassSampler,coords);
    }

    void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
		if(framecount%iFrameAccu!=iFrameAccu-1) discard;
        
        int2 coordsInt = toPixels(coords);
        float refDepth = getDepth(coords);
        float3 refNormal = getNormal(coords);
        
        float4 result = 0;
        float weightSum = 0;
	
        int2 offset = 0;
        int radius = RES_SCALE*iSmoothRadius;
        [loop]
        for(offset.x=-radius;offset.x<=radius;offset.x++) {
        	[loop]
            for(offset.y=-radius;offset.y<=radius;offset.y++) {
                float2 currentCoords = coords+offset*PixelSize();
                
                if(inScreen(currentCoords)) {
                    float4 color = getColorSampler(lightAccuSampler,currentCoords);
                    if(color.a>0) {
                        float depth = getDepth(currentCoords);
                        if(diffT(depth,refDepth,fSmoothDepthThreshold)) {
                            float3 normal = getNormal(currentCoords);
                            if(diffT(normal,refNormal,fSmoothNormalThreshold)) {

                                float d2 = dot(offset,offset)+2;
                                float weight = 1.0/d2;

                                result += color*weight;
                                weightSum += weight;

                            } // end normal
                        } // end depth
                    } // end sampled
                } // end inScreen
            } // end for y
        } // end for x

        if(weightSum>0) {
            result.rgb = saturate(fLightMult*result.rgb/weightSum);
        }
        

        result.a = 1.0;//1.0/iFrameAccu;
        outColor = result;
    }
    
    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        float3 color = getColor(coords).rgb;
        float3 light = getColorSampler(smoothPassSampler,coords).rgb;
        float b = getBrightness(color);

        float3 result = fSourceColor*color+fLightMult*(b<=0.5 ? b : 1-b)*light;
        outPixel = float4(result,1.0);
    }
    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        float4 color = bDebug 
			? getColorSampler(smoothPassSampler,coords)
			: getColorSampler(resultSampler,coords);
        outPixel = color;
    }
    
    
    technique DH_SSR {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_NormalPass;
            RenderTarget = normalTex;
        }
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_ClearAccu;
            RenderTarget = lightPassTex;
            
            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_LightPass;
            RenderTarget = lightPassTex;
            
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
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateAccu;
            RenderTarget = lightAccuTex;
            
            ClearRenderTargets = false;
        }
		pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothPass;
            RenderTarget = smoothPassTex;

            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_UpdateResult;
            RenderTarget = resultTex;

            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_DisplayResult;
        }
    }


}