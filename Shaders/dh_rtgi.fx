#include "Reshade.fxh"

#define BUFFER_SIZE int2(BUFFER_WIDTH,BUFFER_HEIGHT)
#define BUFFER_SIZE3 int3(BUFFER_WIDTH,BUFFER_HEIGHT,BUFFER_WIDTH*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*fDepthMultiplier/1024)
#define NOISE_SIZE 32

#define PI 3.14159265359
#define SQRT2 1.41421356237

#define INV_SQRT_OF_2PI 0.39894228040143267793994605993439  // 1.0/SQRT_OF_2PI
#define INV_PI 0.31830988618379067153776752674503

#define getDepth(c) ReShade::GetLinearizedDepth(c)
#define getNormal(c) (tex2Dlod(normalSampler,float4(c,0,0)).xyz-0.5)*2
#define getColorSampler(s,c) tex2Dlod(s,float4(c,0,0))
#define getColor(c) tex2Dlod(ReShade::BackBuffer,float4(c,0,0))

#define diffT(v1,v2,t) !any(max(abs(v1-v2)-t,0))

namespace DHRTGI {

    texture blueNoiseTex < source ="LDR_RGBA_0.png" ; > { Width = NOISE_SIZE; Height = NOISE_SIZE; MipLevels = 1; Format = RGBA8; };
    sampler blueNoiseSampler { Texture = blueNoiseTex; };

    texture normalTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler normalSampler { Texture = normalTex; };

    texture lightPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler lightPassSampler { Texture = lightPassTex; };
    
    texture lightPassHitTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler lightPassHitSampler { Texture = lightPassHitTex; };

    texture lightPassAOTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler lightPassAOSampler { Texture = lightPassAOTex; };
    
    texture lightAccuTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler lightAccuSampler { Texture = lightAccuTex; };

	texture smoothPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothPassSampler { Texture = smoothPassTex; };
	
    texture smoothAOPassTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothAOPassSampler { Texture = smoothAOPassTex; };
    
	texture smoothPass2Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothPass2Sampler { Texture = smoothPass2Tex; };

	texture smoothAOPass2Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothAOPass2Sampler { Texture = smoothAOPass2Tex; };
    
    texture smoothPass3Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothPass3Sampler { Texture = smoothPass3Tex; };

	texture smoothAOPass3Tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler smoothAOPass3Sampler { Texture = smoothAOPass3Tex; };
    
    texture resultTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler resultSampler { Texture = resultTex; };

    uniform int framecount < source = "framecount"; >;


    uniform bool bDebug <
        ui_category = "Setting";
        ui_label = "Display light only";
    > = false;

    uniform float fRenderScale <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Render scale";
        ui_min = 0.1; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.5;
	
    uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Depth multiplier";
        ui_min = 0.1; ui_max = 100;
        ui_step = 0.1;
    > = 0.5;

    uniform int iFrameAccu <
        ui_type = "slider";
        ui_category = "Setting";
        ui_label = "Temporal accumulation";
        ui_min = 1; ui_max = 16;
        ui_step = 1;
    > = 2;
    
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
        ui_min = 1.0; ui_max = 1000;
        ui_step = 0.1;
    > = 1000;
    
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
        ui_min = 0.001; ui_max = 1;
        ui_step = 0.001;
    > = 0.200;
    
// LIGHT COLOR
    
    uniform float fRayBounce <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Bounce strength";
        ui_min = 0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.2;
        
    uniform float fFadePower <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Distance Fading";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.01;
    > = 1.0;
    
    uniform float fSaturateColor <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Saturate";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.25;
    
    uniform float fSaturateColorPower <
        ui_type = "slider";
        ui_category = "COLOR";
        ui_label = "Saturate";
        ui_min = 1.0; ui_max = 10.0;
        ui_step = 0.01;
    > = 1.5;
    
// AO
    uniform float fAOMultiplier <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Multiplier";
        ui_min = 0.0; ui_max = 5;
        ui_step = 0.01;
    > = 3.0;
    
    uniform int iAODistance <
        ui_type = "slider";
        ui_category = "AO";
        ui_label = "Distance";
        ui_min = 0; ui_max = 16;
        ui_step = 1;
    > = 8;
 
    
// SMOTTHING
    
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
    > = 0.01;

    uniform float fSmoothNormalThreshold <
        ui_type = "slider";
        ui_category = "Smoothing";
        ui_label = "Normal Threshold";
        ui_min = 0; ui_max = 2;
        ui_step = 0.01;
    > = 0.75;
 
// MERGING
    
    uniform float fSourceColor <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Source color";
        ui_min = 0.1; ui_max = 2;
        ui_step = 0.01;
    > = 1.30;
    
    uniform float fSourceDesat <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Source desat";
        ui_min = 0.0; ui_max = 1;
        ui_step = 0.01;
    > = 0.5;
    
    uniform float fLightMult <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light multiplier";
        ui_min = 0.1; ui_max = 10;
        ui_step = 0.01;
    > = 1.5;
    
    uniform float fLightOffset <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light offset";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.01;
    > = 0.15;
    
    uniform float fLightNormalize <
        ui_type = "slider";
        ui_category = "Merging";
        ui_label = "Light normalize";
        ui_min = 0.1; ui_max = 4;
        ui_step = 0.01;
    > = 0.1;
    
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
    
////// COORDINATES
    
    float2 PixelSize() {
        return ReShade::PixelSize/fRenderScale;
    }

    int2 getRenderSize() {
        return BUFFER_SIZE*fRenderScale;
    }

    float2 getRenderCoords(float2 bufferCoords) {
        return bufferCoords/fRenderScale;
    }

    float2 getBufferCoords(float2 renderCoords) {
        return renderCoords*fRenderScale;
    }

    bool inRender(float2 coords) {
    	float2 maxCoords = float2(fRenderScale,fRenderScale)+PixelSize();
        return coords.x<=maxCoords.x && coords.y<=maxCoords.y;
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
    
    bool inScreen(float3 coords) {
        return coords.x>=0 && coords.x<=1
            && coords.y>=0 && coords.y<=1
            && coords.z>=0 && coords.z<=1;
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

    float3 getScreenPosition(float3 wp) {
        float3 result = wp/BUFFER_SIZE3;
        result.xy /= result.z;
        return float3(result.xy+0.5,result.z);
    }
    
    float3 getNormalJitter(float2 coords) {
    	int2 offset = int2((framecount%(16*iFrameAccu)),framecount+(framecount/iFrameAccu));
    	//offset = tex2Dfetch(blueNoiseSampler,offset).yz*255;
    	float3 jitter = normalize(tex2Dfetch(blueNoiseSampler,(offset+coords*BUFFER_SIZE)%(NOISE_SIZE)).rgb)-0.5;
		//float3 normal = (tex2Dlod(normalSampler,float4(coords,0,0)).xyz-0.5)*2;
    	

        //jitter += float3(0,0,float(framecount%iFrameAccu)/iFrameAccu-0.5);
        //return normalize(jitter)+float3(1,0,float((framecount%(2*iFrameAccu)-iFrameAccu)/iFrameAccu));
        return normalize(jitter);
    }

    void PS_NormalPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outNormal : SV_Target0) {
        
        float3 offset = float3(ReShade::PixelSize, 0.0);

        float3 posCenter = getWorldPosition(coords);
        float3 posNorth  = getWorldPosition(coords - offset.zy);
        float3 posEast   = getWorldPosition(coords + offset.xz);
        float3 normal = normalize(cross(posCenter - posNorth, posCenter - posEast));
        
        outNormal = float4(normal/2.0+0.5,1.0);
        
    }
    
    float4 getRayColor(float2 coords) {
    	float4 color = fRayBounce>0 
			? fRayBounce*getColorSampler(resultSampler,coords)+(1-fRayBounce)*getColor(coords)
			: getColor(coords);
			
		if(fSaturateColor>0) {
			float maxChannel = getBrightness(color.rgb);
			if(maxChannel>0) {
				float3 saturatedColor = pow(color.rgb/maxChannel,fSaturateColorPower);
				color.rgb = fSaturateColor*saturatedColor+(1.0-fSaturateColor)*color.rgb;
			}
		}
		return color;
    }

    float4 trace(float3 refWp,float3 lightVector) {

		float stepRatio = 1.0+fRayStepMultiply/10.0;

        float stepLength = 1.0/fRayStepPrecision;
        float3 incrementVector = lightVector*stepLength;
        float traceDistance = 0;
        float3 currentWp = refWp;
        
        bool crossed = false;
        float deltaZ = 0;
        float deltaZbefore = 0;
        float3 lastCross;
		
		bool outSource = false;
        bool firstStep = true;
		
		
        do {
        	currentWp += incrementVector;
            traceDistance += stepLength;
            
            float3 screenCoords = getScreenPosition(currentWp);
			
			bool outScreen = !inScreen(screenCoords);
            
            float3 screenWp = getWorldPosition(screenCoords.xy);
            
            deltaZ = screenWp.z-currentWp.z;
            
            //float3 normal = firstStep && bRayCheckFirstStep ? getNormal(screenCoords.xy) : 0;

            if(firstStep && deltaZ<=0) {

                // wrong direction
                incrementVector = -incrementVector;
                currentWp += incrementVector;
                traceDistance = 0;

                firstStep = false;
            } else if(outSource) {
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
            	if(abs(deltaZ)<=fRayHitDepthThreshold || outScreen) {
            		// hit !
            		return float4(crossed ? lastCross : currentWp,1.0);
            	}
            } else {
            	if(outScreen) {
            		currentWp -= incrementVector;
            		//screenCoords = getScreenPosition(currentWp);
            				
            		//if(screenCoords.z>fSkyDepth) {
            		//	return float4(currentWp,1.0);
            		return 0.0;
				}
            	outSource = abs(deltaZ)>fRayHitDepthThreshold;
            }

            firstStep = false;
            
            deltaZbefore = deltaZ;
            
            stepLength *= stepRatio;
            incrementVector *= stepRatio;

        } while(traceDistance<BUFFER_WIDTH);

        return 0.0;

    }

    void PS_LightPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outHit : SV_Target1, out float4 outDistance : SV_Target2) {
        if(!inRender(coords)) return;

		if(!isPixelTreated(coords)) {
            return;
        }
        
        float2 renderCoords = getRenderCoords(coords);


		float depth = getDepth(renderCoords);
		if(depth>fSkyDepth) {
			return;
		}
		
        float3 targetWp = getWorldPosition(renderCoords);
        float3 targetNormal = getNormalJitter(renderCoords);

        float3 lightVector = reflect(targetWp,targetNormal);
        
        float opacity = 1.0/iFrameAccu;
	        
        
       // float4 hitColor = trace(targetWp,lightVector);
        float4 hitPosition = trace(targetWp,lightVector);
        float3 screenCoords = getScreenPosition(hitPosition.xyz);
        if(hitPosition.a==0) {
        	// no hit
           // outColor = float4(0.25,0.25,0.25,opacity/4);
	  	  outHit = float4(screenCoords,1);	
           // outDistance = outDistance = float4(1,0,0,opacity/4);
        } else {
        	float4 color = getRayColor(screenCoords.xy);
        	float b = getBrightness(color.rgb);
        	
        	float d = max(distance(hitPosition.xyz,targetWp),0);
                        
        	float distance = 1.0+0.02*d;
        	float distanceRatio = 0.1+1.0/pow(distance,fFadePower);//(1-pow(distance,fFadePower)/pow(iRayDistance,fFadePower));
	        
	        //float opacity = bFrameBlur ? 1.0/iFrameAccu : 1;
	        //outColor = float4(hitPosition.a*(0.5+b)*distanceRatio*color.rgb,1.0);
			outColor = float4(hitPosition.a*distanceRatio*color.rgb,opacity);
	  	  outHit = float4(screenCoords,1);	
            outDistance = depth<fWeaponDepth ? float4(1,0,0,1) : float4(d>iAODistance ? 1 : b+(d/iAODistance),0,0,opacity);
        }
    }
    
    void PS_UpdateAccu(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        if(framecount%iFrameAccu!=iFrameAccu-1) discard;
        outPixel = getColorSampler(lightPassSampler,coords);
    }

	void PS_SmoothPass(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outAO : SV_Target1) {
		float2 refBufferCoords = getBufferCoords(coords);

        float refDepth = getDepth(coords);
        float3 refNormal = getNormal(coords);
        
        float4 result = 0;
        float weightSum = 0;

		float4 resultMiss = 0;
        float weightSumMiss = 0;
	
		float4 resultWhite = 0;
        float weightSumWhite = 0;
        
        int2 offset = 0;
        float radius = iSmoothRadius;
        //float step = 1.0/fRenderScale;
        
        float maxRadius2 = 1+radius*radius;
        
        int maxSamples = 0;
        int foundSamples = 0;
        int whiteSamples = 0;
        int missSamples = 0;

        float AO = 0.0;
        int AOSamples = 0;
        
        [loop]
        for(offset.x=-radius;offset.x<=radius;offset.x++) {
        	[loop]
            for(offset.y=-radius;offset.y<=radius;offset.y++) {
                float2 currentCoords = coords+offset*ReShade::PixelSize/fRenderScale;
                
				if(inScreen(currentCoords)) {
                    
                 
                    float depth = getDepth(currentCoords);
                    if(abs(depth-refDepth)<=fSmoothDepthThreshold) {
                    	
                        float3 normal = getNormal(currentCoords);
                        if(diffT(normal,refNormal,fSmoothNormalThreshold)) {
                        	maxSamples++;
                        	
                        	float2 renderCoords = getBufferCoords(currentCoords);
                    
		                    if(dot(offset,offset)<=maxRadius2) {
		                        float4 aoColor = getColorSampler(lightPassAOSampler,renderCoords);
		                        AO += pow(aoColor.r,fAOMultiplier);
		                        AOSamples += 1;
		                    }
                        	
							float4 hitPos = getColorSampler(lightPassHitSampler,renderCoords);
                    		float4 color = getColorSampler(lightAccuSampler,renderCoords);
                   		    float3 hsl = RGBtoHSL(color.rgb);
                        	
                        	
                        	float d2 = 1+dot(offset,offset);
                            float weight = 2+1.0/d2;
                            weight*= hsl.y*hsl.z;
                            
							// hit
                        	result += color*weight;
                            weightSum += weight;
                            foundSamples++;

                        } // end normal
                    } // end depth                 
                } // end inScreen
            } // end for y
        } // end for x

		float3 resultAO = AO/AOSamples;
        outAO = float4(resultAO,1);
        
        if(iSmoothRadius>0 && foundSamples<=1) {
        	// not enough
        	outColor = float4(0,0,0,1);
        	return;
        }  
        
        if(weightSum>0) {
			result.rgb = saturate(fLightMult*result.rgb/weightSum);
		}
        
        result.a = 1.0;//1.0/iFrameAccu;
        outColor = result;
    }
    
    void PS_SmoothPassNoScale(int passNumber,sampler colorSampler,sampler aoSampler, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outAO : SV_Target1) {
		float refDepth = getDepth(coords);
        float3 refNormal = getNormal(coords);
        
        float4 result = 0;
        float weightSum = 0;

		float4 resultMiss = 0;
        float weightSumMiss = 0;
	
		float4 resultWhite = 0;
        float weightSumWhite = 0;
        
        int2 offset = 0;
        float radius = iSmoothRadius*passNumber;
        //float step = 1.0/fRenderScale;
        
        float maxRadius2 = 1+radius*radius;
        
        int maxSamples = 0;
        int foundSamples = 0;
        int whiteSamples = 0;
        int missSamples = 0;
        
        float AO = 0.0;
        int AOSamples = 0;

        [loop]
        for(offset.x=-radius;offset.x<=radius;offset.x+=passNumber) {
        	[loop]
            for(offset.y=-radius;offset.y<=radius;offset.y+=passNumber) {
                float2 currentCoords = coords+offset*ReShade::PixelSize/fRenderScale;
                
				if(inScreen(currentCoords)) {                 
                    float depth = getDepth(currentCoords);
                    if(abs(depth-refDepth)<=fSmoothDepthThreshold) {
                    	float3 normal = getNormal(currentCoords);
                        if(diffT(normal,refNormal,fSmoothNormalThreshold)) {
                        	maxSamples++;
                        	
                        	if(dot(offset,offset)<=maxRadius2) {
		                        float4 aoColor = getColorSampler(aoSampler,currentCoords);
		                        AO += aoColor.r;
		                        AOSamples += 1;
		                    }
                    
							float4 color = getColorSampler(colorSampler,currentCoords);
                   		    float3 hsl = RGBtoHSL(color.rgb);
                        	
                        	float d2 = 1+dot(offset,offset);
                            float weight = 2+1.0/d2;
                            //weight *= hsl.y;
                            
							// hit
                        	result += color*weight;
                            weightSum += weight;
                            foundSamples++;
                            
                        } // end normal
                    } // end depth                 
                } // end inScreen
            } // end for y
        } // end for x
        
        float3 resultAO = AO/AOSamples;
        outAO = float4(resultAO,1);

        if(iSmoothRadius>0 && foundSamples<=1) {
        	// not enough
        	outColor = float4(0,0,0,1);
        	return;
        }

        if(weightSum>0) {
			result.rgb = saturate(result.rgb/weightSum);
			//result.rgb = saturate(fLightMult*result.rgb/weightSum);
		}
        
        result.a = 1.0;//1.0/iFrameAccu;
        outColor = result;
    }
    
    void PS_SmoothPass2(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outAO : SV_Target1) {
    	PS_SmoothPassNoScale(2,smoothPassSampler,smoothAOPassSampler,coords,outColor,outAO);
	}
	
	void PS_SmoothPass3(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0, out float4 outAO : SV_Target1) {
    	PS_SmoothPassNoScale(3,smoothPass2Sampler,smoothAOPass2Sampler,coords,outColor,outAO);
	}
    
    void PS_UpdateResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
        float3 color = getColor(coords).rgb;
        float3 colorHsl = RGBtoHSL(color);
        float3 light = getColorSampler(smoothPass3Sampler,coords).rgb;
        float3 lightHsl = RGBtoHSL(light);
        
        float b = getBrightness(color);
        float lb = getBrightness(light);
        float depth = getDepth(coords);
        
        float ao = max(getColorSampler(smoothAOPass3Sampler,coords).r,b);
        //ao = saturate(max(lb*2,ao));
        
        
        //float3 result = fSourceColor*color+fLightMult*(b<=0.5 ? b : 1-b)*light;
        //float3 result = color*b+(1-b)*fSourceColor*color+fLightMult*(pow(0.5-abs(b-0.5),0.5))*light*saturate(0.1+color);
       //float3 result = color*b+(1-b)*fSourceColor*color+fLightMult*light*(fLightOffset+color);

		float3 colorDesatHsl = colorHsl;
		colorDesatHsl.y *= fSourceDesat;
		colorDesatHsl.z += fLightOffset;
		colorDesatHsl = saturate(colorDesatHsl);
		float3 colorDesat = HSLtoRGB(colorDesatHsl)+fLightOffset;
		float3 lightApply = light*colorDesat;

       float colorRatio = fSourceColor;
       float lightRatio = (1.0-b);//+(1-hDistance);
       float3 result = (colorRatio*color+lightRatio*lightApply)/fLightNormalize;
       result = (result-fLightOffset)/(1.0-fLightOffset);
       
       result = (color*colorRatio+lightApply*(lb+fLightOffset)*lightRatio-fLightNormalize)*ao;
       
       //result *= saturate(ao+fAOMultiplier);

        outPixel = float4(result,1.0);
    }
    
    void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
    {
    	float4 color = getColorSampler(resultSampler,coords);
    	if(bDebug) {
    		float b = getBrightness(color.rgb);
        	float ao = max(getColorSampler(smoothAOPass3Sampler,coords).r,b);
    		color = ao * getColorSampler(smoothPass3Sampler,coords);
    		color.a = 1;
    	}
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
            //PixelShader = PS_FastSmoothPass;
            RenderTarget = smoothPassTex;
            RenderTarget1 = smoothAOPassTex;

            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothPass2;
            RenderTarget = smoothPass2Tex;
            RenderTarget1 = smoothAOPass2Tex;

            ClearRenderTargets = false;
        }
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_SmoothPass3;
            RenderTarget = smoothPass3Tex;
            RenderTarget1 = smoothAOPass3Tex;

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