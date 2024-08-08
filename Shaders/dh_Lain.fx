////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_Lain 1.1 (2024-08-09)
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

#define BUFFER_SIZE int2(BUFFER_WIDTH,BUFFER_HEIGHT)

#ifndef PRIMARY_TEXTURE
 #define PRIMARY_TEXTURE "lain_blood_1024.png"
#endif
#ifndef SECONDARY_TEXTURE
 #define SECONDARY_TEXTURE "lain_cloud_1024.png"
#endif
namespace Lain11 {

// Uniforms
	
	
	uniform bool bTest <
	    ui_category = "Test";
	> = false;
	uniform bool bTest2 <
	    ui_category = "Test";
	> = false;
	
//// COMMONS
	uniform bool bDebug <
	    ui_category = "Common";
		ui_label = "Debug";
	> = false;
	
	uniform float fBrightnessLimit <
	    ui_category = "Common";
		ui_label = "Brightness Limit";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.10;
	
//// BORDERS
	uniform bool bBorder <
	    ui_category = "Borders";
		ui_label = "Enable";
	> = false;
	
	uniform bool bBorderPrecise <
	    ui_category = "Borders";
		ui_label = "Precise method";
	> = false;
	
	uniform float fBorderIntensity <
	    ui_category = "Borders";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.2;
	
	uniform int iBorderRadius <
	    ui_category = "Borders";
		ui_label = "Radius";
		ui_type = "slider";
	    ui_min = 1;
	    ui_max = 128;
	    ui_step = 1;
	> = 32;

	uniform int iBorderStepSize <
	    ui_category = "Borders";
		ui_label = "Step size";
		ui_type = "slider";
	    ui_min = 1;
	    ui_max = 8;
	    ui_step = 1;
	> = 3;
	
	uniform float3 cBorderColor <
	    ui_category = "Borders";
		ui_label = "Color";
		ui_type = "color";
	> = float3(1,0,0);
	
///// PRIMARY

	uniform bool bPrimaryDepth <
	    ui_category = "Primary texture";
		ui_label = "Use depth";
	> = true;
	
	uniform float fPrimaryIntensity <
	    ui_category = "Primary texture";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.4;
	
	uniform float fPrimaryCurvePower <
	    ui_category = "Primary texture";
		ui_label = "Curve power";
		ui_type = "slider";
	    ui_min = 1.0;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 2.5;

	uniform float fPrimaryScale <
	    ui_category = "Primary texture";
		ui_label = "Scale";
		ui_type = "slider";
	    ui_min = 0.1;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 1.0;
	
	uniform bool bPrimaryForceColor <
	    ui_category = "Primary texture";
		ui_label = "Force Color";
	> = true;
	
	uniform float3 cPrimaryColor <
	    ui_category = "Primary texture";
		ui_label = "Color";
		ui_type = "color";
	> = float3(1,0,0);

///// SECONDARY

	uniform bool bSecondaryDepth <
	    ui_category = "Secondary texture";
		ui_label = "Use depth";
	> = false;
	
	uniform float fSecondaryIntensity <
	    ui_category = "Secondary texture";
		ui_label = "Intensity";
		ui_type = "slider";
	    ui_min = 0.0;
	    ui_max = 1.0;
	    ui_step = 0.01;
	> = 0.30;
	
	uniform float fSecondaryCurvePower <
	    ui_category = "Secondary texture";
		ui_label = "Curve power";
		ui_type = "slider";
	    ui_min = 1.0;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 3.0;

	uniform float fSecondaryScale <
	    ui_category = "Secondary texture";
		ui_label = "Scale";
		ui_type = "slider";
	    ui_min = 0.1;
	    ui_max = 8.0;
	    ui_step = 0.1;
	> = 1.5;
	
	uniform bool bSecondaryForceColor <
	    ui_category = "Secondary texture";
		ui_label = "Force Color";
	> = true;
	
	uniform float3 cSecondaryColor <
	    ui_category = "Secondary texture";
		ui_label = "Color";
		ui_type = "color";
	> = float3(133.0/255.0,0,174.0/255.0);

	
// Textures
	texture PrimaryTex <source=PRIMARY_TEXTURE;  > { Width = 1024; Height = 1024; };
	sampler PrimarySampler { Texture = PrimaryTex;AddressU=REPEAT;AddressV=REPEAT;AddressW=REPEAT;};
	
	texture SecondaryTex <source=SECONDARY_TEXTURE; > { Width = 1024; Height = 1024; };
	sampler SecondarySampler { Texture = SecondaryTex;AddressU=REPEAT;AddressV=REPEAT;AddressW=REPEAT;};

// Functions

	float getBrightness(float3 color) {
		return (color.r+color.g+color.b)/3.0;
	}
	
	
	float4 getColor(float2 coords) {
		return tex2Dlod(ReShade::BackBuffer,float4(coords,0.0,0.0));
	}
	
	
	float3 getBorder(float2 coords,float brightness) {
		if(!bBorder || iBorderRadius<=0) {
			return 0;
		}
		
		float borderDist = -1;
		float borderScore = 99999;
		
		float2 delta = 0;
		if(!bBorderPrecise) {
			for(float dist=0;dist<=iBorderRadius;dist+=iBorderStepSize) {
				for(delta.x=-dist;delta.x<=dist;delta.x+=max(1,dist)) {
					for(delta.y=-dist;delta.y<=dist;delta.y+=max(1,dist)) {
					
						float2 searchCoords = coords + delta*ReShade::PixelSize;
						float4 searchColor = getColor(searchCoords);
						float seachB = getBrightness(searchColor.rgb);
						if(seachB>=fBrightnessLimit) {
							float score = 10*seachB*dist/iBorderRadius;
							if(borderScore>score) {
								borderDist = dist;
								borderScore = score;
							}
						}
					}
				}
			}
			
		} else {
			for(delta.x=-iBorderRadius;delta.x<=iBorderRadius;delta.x+=iBorderStepSize) {
				for(delta.y=-iBorderRadius;delta.y<=iBorderRadius;delta.y+=iBorderStepSize) {
					float dist = length(delta);
					
					float2 searchCoords = coords + delta*ReShade::PixelSize;
					float4 searchColor = getColor(searchCoords);
					float seachB = getBrightness(searchColor.rgb);
					if(seachB>=fBrightnessLimit) {
						float score = 10*seachB*dist/iBorderRadius;
						if(borderScore>score) {
							borderDist = dist;
							borderScore = score;
						}
					}
				}
			}
		}
		

		
		if(borderDist!=-1) {
			float ratio = fBorderIntensity*saturate(1.0-brightness/fBrightnessLimit);
			return cBorderColor*ratio*saturate(1.0-borderScore)*float(iBorderRadius-borderDist+1)/iBorderRadius;
		}
		
		return 0;
	}
	
	float3 getTextureValue(
		sampler textureSampler, 
		float2 coords,
		bool useDepth, float depth,
		float scale,
		bool forceColor,float3 color,
		float brightness, float intensity, float curve
	) {
		coords /= scale;
		coords.x *= float(BUFFER_WIDTH)/BUFFER_HEIGHT;
		if(useDepth) {
			coords *= pow(2.0,depth);
		}
		
		float3 tex = tex2D(textureSampler,coords).rgb;
		if(forceColor) {
			
			tex = getBrightness(tex)*color/getBrightness(color);
		}
		
		float ratio = intensity*pow(saturate(1.0-brightness/fBrightnessLimit),curve);
		
		return tex*ratio;
	}


// Pixel shaders

	void PS_result(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
	{
		float3 color = getColor(coords).rgb;
		float brightness = getBrightness(color.rgb);
		
		if(brightness<=fBrightnessLimit) {
			float depth = ReShade::GetLinearizedDepth(coords);
			
			float3 addedColor = 0;
			
			// BORDER
			addedColor = getBorder(coords,brightness);
			
			// PRIMARY
			addedColor = max(addedColor,
							getTextureValue(
								PrimarySampler,coords,
								bPrimaryDepth,depth,
								fPrimaryScale,
								bPrimaryForceColor,cPrimaryColor,
								brightness,fPrimaryIntensity,fPrimaryCurvePower
							)
						);
			
			// SECONDARY
			addedColor = max(addedColor,
							getTextureValue(
								SecondarySampler,coords,
								bSecondaryDepth,depth,
								fSecondaryScale,
								bSecondaryForceColor,cSecondaryColor,
								brightness,fSecondaryIntensity,fSecondaryCurvePower
							)
						);
			
			if(bDebug) {
				color = addedColor;
			} else {
				color += addedColor;
			}
			
		} else if(bDebug) {
			color = 0;
		}
		
		outPixel = float4(color,1.0);
	}
	
// Techniques

	technique DH_Lain11 <
        ui_label = "DH_Lain 1.1";
	>
	{
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_result;
		}
	}

}