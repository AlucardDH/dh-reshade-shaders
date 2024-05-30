#include "Reshade.fxh"
#define PI 3.14159265359

#ifndef AhOh_RENDER_SCALE
 #define AhOh_RENDER_SCALE 0.5
#endif

#define getColorSamplerLod(s,c,l) tex2Dlod(s,float4((c).xy,0,l))

uniform int random < source = "random"; min = 0; max = BUFFER_WIDTH*BUFFER_HEIGHT; >;

uniform int iRadius <ui_category="Quality"; ui_type = "slider"; ui_label = "Radius"; ui_min = 1; ui_max = 256; ui_step = 1;> = 128;
uniform int iSamples <ui_category="Quality"; ui_type = "slider"; ui_label = "Samples count"; ui_min = 1; ui_max = 256; ui_step = 1;> = 128;

uniform bool bDenoise <ui_category="Denoising"; ui_label = "Enable";> = true;
uniform int iDenoiseStep <ui_category="Denoising"; ui_type = "slider"; ui_label = "Radius"; ui_min = 1; ui_max = 8; ui_step = 1;> = 2;
uniform float fDenoiseLod <ui_category="Denoising"; ui_type = "slider"; ui_label = "LOD"; ui_min = 0.0; ui_max = 5.0; ui_step = 0.1;> = 1.0;

uniform bool bHighlights <ui_category="Highlights"; ui_label = "Highligts"; > = true;
uniform float fHighlightsThreshold <ui_category="Highlights"; ui_type = "slider"; ui_label = "Highligts threshold"; ui_min = 0; ui_max = 1.0; ui_step = 0.001;> = 0.75;
uniform float fHighlightsStrength <ui_category="Highlights"; ui_type = "slider"; ui_label = "Highligts strength"; ui_min = 0; ui_max = 4; ui_step = 0.001;> = 1.0;

uniform bool bStaticNoise <ui_category="Debug"; ui_label = "Static noise";> = false;
uniform bool bDebug <ui_category="Debug"; ui_label = "Debug";> = false;

/*
uniform bool bTest = true;
uniform float fTest < ui_type = "slider"; ui_label = "fTest"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;> = 0.0;
uniform float fTest2 < ui_type = "slider"; ui_label = "fTest2"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;> = 0.0;
uniform int iTest < ui_type = "slider"; ui_label = "iTest"; ui_min = 1; ui_max = 64; ui_step = 1;> = 1;
*/

texture rawAoTex { Width = BUFFER_WIDTH*AhOh_RENDER_SCALE; Height = BUFFER_HEIGHT*AhOh_RENDER_SCALE; Format = RG16F; MipLevels = 6;  };
sampler rawAoSampler { Texture = rawAoTex; MinLOD = 0.0f; MaxLOD = 5.0f;};

texture denoisedAoTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
sampler denoisedAoSampler { Texture = denoisedAoTex; };
      
float randomValue(inout uint seed) {
	seed = seed * 747796405 + 2891336453;
	uint result = ((seed>>((seed>>28)+4))^seed)*277803737;
	return ((result>>22)^result)/4294967295.0;
}

bool inScreen(float2 coords) {
	return coords.x>=0 && coords.y>=0 && coords.x<=1 && coords.y<=1;
}


    								
void PS_AhOh(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float2 outPixel : SV_Target) {
	float3 coordsInt = float3(coords * int2(BUFFER_WIDTH,BUFFER_HEIGHT),ReShade::GetLinearizedDepth(coords));
	uint seed = (coordsInt.x+coordsInt.y*BUFFER_WIDTH+(bStaticNoise?0:random))%(BUFFER_WIDTH*BUFFER_HEIGHT); 
	
	float AO;
	
	bool sky = coordsInt.z>0.999;
	if(sky) {
		AO = 1;
	} else {
		float d;
		float2 currentCoords;
		
		float dir;
		float2 delta;
		int validSamples = 0;
		
		for(int s=1;s<=iSamples;s++) {
			dir = randomValue(seed)*2*PI;
			delta = float2(cos(dir),sin(dir));
		
			float r = iRadius*s*randomValue(seed)/iSamples;
			
			currentCoords = float2(coordsInt.xy+delta*r)/float2(BUFFER_WIDTH,BUFFER_HEIGHT);
			if(!inScreen(currentCoords)) continue;
			float depth = ReShade::GetLinearizedDepth(currentCoords);
			if(depth+0.21*coordsInt.z<coordsInt.z) continue;
			d = depth-coordsInt.z+1.0/RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
			validSamples++;
			AO += saturate(d*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
			
			
		}
		AO = validSamples>0 ? AO/validSamples : 1;
	}
	
	outPixel = float2(AO,sky ? 0 : 1);
}

void PS_Denoise(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float2 outPixel : SV_Target) {
	float2 refAO = tex2D(rawAoSampler,coords).rg;
	if(bDenoise && refAO.g>0) {
		float refDepth = ReShade::GetLinearizedDepth(coords);
		
		float3 pixelSize = float3(ReShade::PixelSize,0)/AhOh_RENDER_SCALE;
		float2 sumAO = float2(refAO.r,1);
		
		float2 currentCoords;
		float2 currentAO;
		float dz;
		float depth;
			
		for(int step=1;step<=iDenoiseStep;step++) {
			
	
			currentCoords = coords + pixelSize.xz*step*(1+refDepth) + ((step+random)%3-1) * pixelSize.zy*(step-1);
			if(inScreen(currentCoords.xy)) {
				currentAO = getColorSamplerLod(rawAoSampler,currentCoords,fDenoiseLod).rg;
				if(currentAO.g>0) {
					depth = ReShade::GetLinearizedDepth(currentCoords);
					dz = saturate((1.0-abs(refDepth - depth)*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*(1.0-refDepth)))/step;
					sumAO.r += currentAO.r * dz;
					sumAO.g += dz;
				}
			}
			
			currentCoords = coords - pixelSize.xz*step*(1+refDepth) - ((step+random)%3-1) * pixelSize.zy*(step-1);
			if(inScreen(currentCoords.xy)) {
				currentAO = getColorSamplerLod(rawAoSampler,currentCoords,fDenoiseLod).rg;
				if(currentAO.g>0) {
					depth = ReShade::GetLinearizedDepth(currentCoords);
					dz = saturate((1.0-abs(refDepth - depth)*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*(1.0-refDepth)))/step;
					sumAO.r += currentAO.r * dz;
					sumAO.g += dz;
				}
			}
			
			currentCoords = coords + pixelSize.zy*step*(1+refDepth) + ((step+random)%3-1) * pixelSize.xz*(step-1);
			if(inScreen(currentCoords.xy)) {
				currentAO = getColorSamplerLod(rawAoSampler,currentCoords,fDenoiseLod).rg;
				if(currentAO.g>0) {
					depth = ReShade::GetLinearizedDepth(currentCoords);
					dz = saturate((1.0-abs(refDepth - depth)*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*(1.0-refDepth)))/step;
					sumAO.r += currentAO.r * dz;
					sumAO.g += dz;
				}
			}
			
			currentCoords = coords - pixelSize.zy*step*(1+refDepth) - ((step+random)%3-1) * pixelSize.xz*(step-1);
			if(inScreen(currentCoords.xy)) {
				currentAO = getColorSamplerLod(rawAoSampler,currentCoords,fDenoiseLod).rg;
				if(currentAO.g>0) {
					depth = ReShade::GetLinearizedDepth(currentCoords);
					dz = saturate((1.0-abs(refDepth - depth)*RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*(1.0-refDepth)))/step;
					sumAO.r += currentAO.r * dz;
					sumAO.g += dz;
				}
			}
		}
		
		refAO.r = sumAO.g>0 ? saturate(sumAO.r/sumAO.g) : 1;
	}
	
	outPixel = refAO;
}



void PS_DisplayResult(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target0)
{	
    float4 AO = tex2D(denoisedAoSampler,coords);
    AO = float4(AO.r,AO.r,AO.r,AO.g);
    bool sky = AO.g > 0.999;
	if(bDebug) {
		if(bHighlights && !sky) {
			if(AO.x>=fHighlightsThreshold) {
				AO = float3(1,(AO.gb-fHighlightsThreshold)*fHighlightsStrength);
				AO.b = saturate(AO.b);
				if(AO.g>1) {
					AO.r = 0;
					AO.g = saturate(1-(AO.g-1));
				}
			} else {
				AO = float3(AO.x/fHighlightsThreshold,0,0);
			}
		}
		outPixel = float4(AO.rgb,1);
	} else {
		float3 c = tex2D(ReShade::BackBuffer,coords).rgb;
		if(sky) {
			outPixel = float4(c,1);
		} else if(bHighlights) {
			if(AO.x>=fHighlightsThreshold) {
				c *= 1+(AO.rgb-fHighlightsThreshold)*fHighlightsStrength;
			} else {
				c *= AO.x/fHighlightsThreshold;
			}
			outPixel = float4(saturate(c),1);
		} else {
			outPixel = float4(AO.rgb*c,1);
		}
	}
}

technique DH_AhOh <> {
	pass {
		VertexShader = PostProcessVS; 
		PixelShader = PS_AhOh;
        RenderTarget = rawAoTex;
	}
	pass {
		VertexShader = PostProcessVS; 
		PixelShader = PS_Denoise;
        RenderTarget = denoisedAoTex;
	}
	pass {
		VertexShader = PostProcessVS; 
		PixelShader = PS_DisplayResult;
	}
}