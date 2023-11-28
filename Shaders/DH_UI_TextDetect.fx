////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UI_TextDetect 1.1.0
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://github.com/AlucardDH/dh-reshade-shaders
//
////////////////////////////////////////////////////////////////////////////////////////////////
#include "Reshade.fxh"

namespace DH_UI_TextDetect_110 {

// Uniforms
uniform int framecount < source = "framecount"; >;


uniform bool bDebug <
	ui_label = "Debug view";
> = false;


/*
uniform bool bTest = true; 
uniform bool bTest2 = true; 
uniform float fTest<
	ui_type = "slider";
    ui_min = 0;
    ui_max = 1;
    ui_step = 0.001;
> = 1.0; 
*/

uniform int iTextMaxThickness <
    ui_category = "Detection";
	ui_label = "Text max thicnkess";
	ui_type = "slider";
    ui_min = 1;
    ui_max = 16;
    ui_step = 1;
> = 6;

uniform float fMinTextBrightness <
    ui_category = "Detection";
	ui_label = "Min text brightness";
	ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.80;

uniform float fMaxDiffColor <
    ui_category = "Detection";
	ui_label = "Max color diff";
	ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.50;

uniform float fMinDiffBrightness <
    ui_category = "Detection";
	ui_label = "Min diff brightness";
	ui_type = "slider";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.28;

uniform int iTextOutline <
    ui_category = "Detection";
	ui_label = "Text outline";
	ui_type = "slider";
    ui_min = 0.0;
    ui_max = 8;
    ui_step = 1;
> = 1;

uniform bool bRTEnabled <
    ui_category = "Protect RT effects";
	ui_label = "Enable";
> = true;

// Textures

	texture dh_ui_savedTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler dh_ui_savedSampler { Texture = dh_ui_savedTex; };

	texture dh_ui_textTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
	sampler dh_ui_textSampler { Texture = dh_ui_textTex; };
    
// Functions



	bool inScreen(float v) {
		return v>=0 && v<=1;
	}

	bool inScreen(float2 coords) {
		return inScreen(coords.x) && inScreen(coords.y);
	}
	
	float maxOf3(float3 v) {
		return max(max(v.r,v.g),v.b);
	}

	float getBrightness(float3 color) {
		return maxOf3(color);
	}
	
	float getColorDistance(float3 refColor, float3 color) {
		float3 diff = abs(refColor-color);
		return maxOf3(diff);
	}
	

	float isText(float2 coords,float3 color) {
		float brightness = getBrightness(color);
		bool isLight =  brightness>=fMinTextBrightness;
		if(!isLight) {
			return 0.0;
		}

		
		int2 size = 0;
		float2 delta = 0.0;
		int border = 0;
		for(int d=1;d<=iTextMaxThickness*2;d++) {
			delta.x += 1.0;
			float2 currentCoords = coords + delta*ReShade::PixelSize;
			if(inScreen(currentCoords)) {
				float3 searchColor = tex2Dlod(ReShade::BackBuffer,float4(currentCoords,0,0)).rgb;
				if(getColorDistance(color,searchColor)<=fMaxDiffColor) {
					size.x++;
					continue;
				}
				float searchBrightness = getBrightness(searchColor);
				if(searchBrightness<=abs(brightness-fMinDiffBrightness)) border++;
				break;
			}
		}
		
		delta = 0.0;
		for(int d=1;d<=iTextMaxThickness*2;d++) {
			delta.x -= 1.0;
			float2 currentCoords = coords + delta*ReShade::PixelSize;
			if(inScreen(currentCoords)) {
				float3 searchColor = tex2Dlod(ReShade::BackBuffer,float4(currentCoords,0,0)).rgb;
				if(getColorDistance(color,searchColor)<=fMaxDiffColor) {
					size.x++;
					continue;
				}
				float searchBrightness = getBrightness(searchColor);
				if(searchBrightness<=abs(brightness-fMinDiffBrightness)) border++;
				break;				
			}
		}
		
		delta = 0.0;
		for(int d=1;d<=iTextMaxThickness*2;d++) {
			delta.y += 1.0;
			float2 currentCoords = coords + delta*ReShade::PixelSize;
			if(inScreen(currentCoords)) {
				float3 searchColor = tex2Dlod(ReShade::BackBuffer,float4(currentCoords,0,0)).rgb;
				if(getColorDistance(color,searchColor)<=fMaxDiffColor) {
					size.y++;
					continue;
				}
				float searchBrightness = getBrightness(searchColor);
				if(searchBrightness<=abs(brightness-fMinDiffBrightness)) border++;
				break;
			}
		}
		
		delta = 0.0;
		for(int d=1;d<=iTextMaxThickness*2;d++) {
			delta.y -= 1.0;
			float2 currentCoords = coords + delta*ReShade::PixelSize;
			if(inScreen(currentCoords)) {
				float3 searchColor = tex2Dlod(ReShade::BackBuffer,float4(currentCoords,0,0)).rgb;
				if(getColorDistance(color,searchColor)<=fMaxDiffColor) {
					size.y++;
					continue;
				}
				float searchBrightness = getBrightness(searchColor);
				if(searchBrightness<=abs(brightness-fMinDiffBrightness)) border++;
				break;
			}
		}
		
		if(border>=2) {
			return 1.0;
		}
		return 0.0;
	}


// Pixel shaders

	void PS_save(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outText : SV_Target, out float4 outSaved : SV_Target1)
	{
		float4 sourceColor = tex2D(ReShade::BackBuffer,coords);
		outText = isText(coords,sourceColor.rgb);
		outSaved = sourceColor;
	}
	
	void PS_RT_protect(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outColor : SV_Target)
	{
		if(!bRTEnabled) {
			discard;
		}
		float ui = tex2D(dh_ui_textSampler,coords).r;
		float3 result;
		
		if(ui>0) {
			result = 0;
		} else {
			result = tex2D(ReShade::BackBuffer,coords).rgb;
		}
		outColor = float4(result,1.0);
	}

	void PS_restore(in float4 position : SV_Position, in float2 coords : TEXCOORD, out float4 outPixel : SV_Target)
	{
		float text = tex2D(dh_ui_textSampler,coords).r;
		if(text<0.9) {
			text = 0;
			if(iTextOutline>0) {
				float2 delta = 0;
				float maxDist2 = iTextOutline*iTextOutline;
				float dist = maxDist2+1;
				
				[loop]
				for(delta.x=-iTextOutline;delta.x<=iTextOutline;delta.x+=1.0) {
					for(delta.y=-iTextOutline;delta.y<=iTextOutline;delta.y+=1.0) {
						float dist2 = dot(delta,delta);
						if(dist2<=dist) {
							float2 searchCoord = coords + delta*ReShade::PixelSize;
							if(inScreen(searchCoord)) {
								float searchText = tex2Dlod(dh_ui_textSampler,float4(searchCoord,0,0)).r;
								if(searchText>=0.9) {
									dist = dist2;
								}
							}
						}
					}
				}
				if(dist<maxDist2+1) {
					text = 1.0 - pow(dist/maxDist2,0.5);
				}
			}
		}
		if(bDebug) { 
			outPixel = float4(text,0,0,1);
			return;
		}
		float3 color = tex2D(ReShade::BackBuffer,coords).rgb;
		float3 saved = tex2D(dh_ui_savedSampler,coords).rgb;
		outPixel = float4(color*(1.0-text)+saved*text,1.0);
	}
	
// Techniques

	technique DH_UI_TextDetect_before <
            ui_label = "DH_UI_TextDetect BEFORE 1.1.0";
	        ui_tooltip = 
	            "_____________ DH_UI_TextDetect _____________\n"
	            "\n"
	            "         version 1.1.0 by AlucardDH\n"
	            "\n"
	            "_____________________________________________";
	> {
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_save;
			RenderTarget = dh_ui_textTex;
			RenderTarget1 = dh_ui_savedTex;
		}
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_RT_protect;
		}
	}

	technique DH_UI_TextDetect_after <
            ui_label = "DH_UI_TextDetect AFTER 1.1.0";
	        ui_tooltip = 
	            "_____________ DH_UI_TextDetect _____________\n"
	            "\n"
	            "         version 1.1.0 by AlucardDH\n"
	            "\n"
	            "_____________________________________________";
	> {
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = PS_restore;
		}
	}

}