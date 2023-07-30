#include "Reshade.fxh"

namespace DH_Lain {

// Uniforms

	uniform bool bBorderBleed <
	    ui_category = "Borders";
		ui_label = "Bleed Borders";
	> = false;
	
	uniform int iBleedRadius <
	    ui_category = "Borders";
		ui_label = "Bleed radius";
		ui_type = "slider";
	    ui_min = 0;
	    ui_max = 128;
	    ui_step = 1;
	> = 48;

	uniform int iBleedSteps <
	    ui_category = "Borders";
		ui_label = "Bleed steps";
		ui_type = "slider";
	    ui_min = 1;
	    ui_max = 16;
	    ui_step = 1;
	> = 6;
	
	uniform float fBleedIntensity <
	    ui_category = "Borders";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.5;
	
	uniform bool bUseDepth <
	    ui_category = "Blood";
		ui_label = "Use depth";
	> = true;

	uniform float fBrightnessLimit <
	    ui_category = "Blood";
		ui_label = "Brightness Limit";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.05;
	
	uniform float fIntensity <
	    ui_category = "Blood";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.4;
	
	uniform float fCurvePower <
	    ui_category = "Blood";
		ui_label = "Curve power";
		ui_type = "slider";
	    ui_min = 1.0;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 2.5;

	uniform float fScale <
	    ui_category = "Blood";
		ui_label = "Scale";
		ui_type = "slider";
	    ui_min = 0.1;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 1.0;

	
	uniform float fCloudIntensity <
	    ui_category = "Cloud";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.30;
	
	uniform float fCloudCurvePower <
	    ui_category = "Cloud";
		ui_label = "Curve power";
		ui_type = "slider";
	    ui_min = 1.0;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 3.0;

	uniform float fCloudScale <
	    ui_category = "Cloud";
		ui_label = "Scale";
		ui_type = "slider";
	    ui_min = 0.1;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 1.5;

	
// Textures
	texture BloodStainTex < source ="lain_blood_1024.png" ; > { Width = 1024; Height = 1024; };
	sampler BloodStainSampler { Texture = BloodStainTex; AddressU = REPEAT;	AddressV = REPEAT;	AddressW = REPEAT;};
	
	texture CloudStainTex < source ="lain_cloud_1024.png" ; > { Width = 1024; Height = 1024; };
	sampler CloudStainSampler { Texture = CloudStainTex; AddressU = REPEAT;	AddressV = REPEAT;	AddressW = REPEAT;};

// Functions

	float getBrightness(float3 color) {
		return (color.r+color.g+color.b)/3.0;
	}
	
	
	float4 getColor(float2 coords) {
		return tex2Dlod(ReShade::BackBuffer,float4(coords,0.0,0.0));
	}


// Pixel shaders

	void PS_result(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
	{
		float4 color = getColor(coords);
		float b = getBrightness(color.rgb);
		float3 result = color.rgb;
		if(b<=fBrightnessLimit) {
			float2 coordsBlood = coords/fScale;
			coordsBlood.x *= float(BUFFER_WIDTH)/BUFFER_HEIGHT;

			if(bUseDepth) {
				coordsBlood *= pow(2.0,ReShade::GetLinearizedDepth(coords));
			}
			
			float3 blood = tex2D(BloodStainSampler,coordsBlood).rgb;
			float bloodRatio = fIntensity*pow(saturate(1.0-b/fBrightnessLimit),fCurvePower);
			blood *= bloodRatio;
			
		
			if(bBorderBleed && iBleedRadius>0) {
				float stepSize = iBleedRadius/iBleedSteps;
				int2 delta = 0;
				int found = 0;
				float radius = stepSize;
				for(radius=stepSize;!found && radius<=iBleedRadius;radius+=stepSize) {
					delta.x = -radius;
					[loop]
					for(delta.y=-radius;!found && delta.y<=radius;delta.y++) {
						float2 searchCoords = coords + delta*ReShade::PixelSize;
						float4 searchColor = getColor(searchCoords);
						float seachB = getBrightness(searchColor.rgb);
						if(seachB>=fBrightnessLimit) {
							found = 1;
						}
					}
					if(found) break;
					delta.x = radius;
					[loop]
					for(delta.y=-radius;!found && delta.y<=radius;delta.y++) {
						float2 searchCoords = coords + delta*ReShade::PixelSize;
						float4 searchColor = getColor(searchCoords);
						float seachB = getBrightness(searchColor.rgb);
						if(seachB>=fBrightnessLimit) {
							found = 1;
						}
					}
					if(found) break;
					delta.y = -radius;
					[loop]
					for(delta.x=-radius+1;!found && delta.x<=radius-1;delta.x++) {
						float2 searchCoords = coords + delta*ReShade::PixelSize;
						float4 searchColor = getColor(searchCoords);
						float seachB = getBrightness(searchColor.rgb);
						if(seachB>=fBrightnessLimit) {
							found = 1;
						}
					}
					if(found) break;
					delta.y = radius;
					[loop]
					for(delta.x=-radius+1;!found && delta.x<=radius-1;delta.x++) {
						float2 searchCoords = coords + delta*ReShade::PixelSize;
						float4 searchColor = getColor(searchCoords);
						float seachB = getBrightness(searchColor.rgb);
						if(seachB>=1.0-fBrightnessLimit) {
							found = 1;
						}
					}
				}
				
				if(found>0) {
					blood.r = max(blood.r,fBleedIntensity*bloodRatio*float(iBleedRadius-radius+1)/iBleedRadius);//-blood.r;
				}
			}
			
			float2 coordsCloud = coords/fCloudScale;
			coordsCloud.x *= float(BUFFER_WIDTH)/BUFFER_HEIGHT;
			
			float3 cloud = tex2D(CloudStainSampler,coordsCloud).rgb;
			cloud *= fCloudIntensity*pow(saturate(1.0-b/fBrightnessLimit),fCloudCurvePower);
			
			
			result += max(blood,cloud);
			
			
			
		}
		
		outPixel = float4(result,1.0);
	}
	
// Techniques

	technique DH_Lain <
	>
	{
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_result;
		}
	}

}