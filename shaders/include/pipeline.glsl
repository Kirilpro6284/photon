/*
0  | rgba16f | fullscreen        | overlays, vanilla sky (solid -> deferred), forwardly rendered objects (translucent -> composite), post-processing color (composite)
1  | rg32ui  | fullscreen        | gbuffer data (solid -> composite)
2  | rgba16f | TAA render scale  | clouds history
3  | rgb11f  | TAA render scale  | scene radiance (deferred -> composite)
4  | r8      | TAA render scale  | clouds pixel age
5  | rgba16  | TAA render scale  | low-res clouds (deferred), indirect lighting data (deferred), responsive AA flag and depth min/max (composite)
6  | rgba16f | TAA render scale  | volumetric fog transmittance (composite), taa min color (composite)
7  | rgba16f | TAA render scale  | atmosphere scattering (deferred -> composite), volumetric fog scattering (composite), taa max color (composite)
8  | rgba16f | fullscreen        | scene history
9  | rgba16  | fullscreen        | atmosphere scattering lut (deferred), water mask (translucent -> composite)
10 | rgba16f | TAA render scale  | indirect lighting history (deferred), 3D noise for fog (composite)
11 | r32f    | fullscreen        | reversed-z depth buffer (translucent)
12 | r32f    | fullscreen        | reversed-z depth buffer (solid)
13 | rgba16f | TAA render scale  | previous frame depth, previous frame light levels
14 | r32f    | fullscreen        | temporally stable depth buffer
15 | rgb11f  | 960x1080          | reprojected scene history for HBIL, cloud shadow map, bloom buffer
16 | rgba16f | fullscreen        | voxy translucents
17 | rgba16  | fullscreen        | voxy water mask

const int colortex0Format  = RGBA16F;
const int colortex2Format  = RGBA16F;
const int colortex3Format  = R11F_G11F_B10F;
const int colortex4Format  = R8I;
const int colortex5Format  = RGBA16;
const int colortex6Format  = RGBA16F;
const int colortex7Format  = RGBA16F;
const int colortex8Format  = RGBA16F;
const int colortex9Format  = RGBA16;
const int colortex10Format = RGBA16F;
const int colortex11Format = R32F;
const int colortex12Format = R32F;
const int colortex13Format = RGBA16F;
const int colortex14Format = R32F;
const int colortex15Format = R11F_G11F_B10F;
const int colortex16Format = RGBA16F;
const int colortex17Format = RGBA16;

const int shadowcolor0Format = R11F_G11F_B10F;

const bool colortex0Clear  = true;
const bool colortex1Clear  = false;
const bool colortex2Clear  = false;
const bool colortex3Clear  = false;
const bool colortex4Clear  = false;
const bool colortex5Clear  = false;
const bool colortex6Clear  = false;
const bool colortex7Clear  = false;
const bool colortex8Clear  = false;
const bool colortex9Clear  = true;
const bool colortex10Clear = false;
const bool colortex11Clear = true;
const bool colortex12Clear = true;
const bool colortex13Clear = false;
const bool colortex14Clear = false;
const bool colortex15Clear = false;
const bool colortex16Clear = true;
const bool colortex17Clear = true;

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex9ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/
// Select texture format for colortex1 based on how much data is required
// This is formatted like this because OF doesn't detect #if defined so I can't use #elif or ||
#ifdef MC_GL_VENDOR_INTEL
	// Use floating point texture format for colortex1, even though it stores unsigned integers
	// This really shouldn't work, but it seems to be required to work properly on Intel and Mesa drivers
	#ifdef SPECULAR_MAP
	/*
		const int colortex1Format = RGBA32F;
	*/
	#else
		#ifdef NORMAL_MAP
		/*
			const int colortex1Format = RGB32F;
		*/
		#else
		/*
			const int colortex1Format = RG32F;
		*/
		#endif
	#endif
#else
	#ifdef MC_GL_VENDOR_MESA
	 	// Mesa drivers also require the floating point texture format hack
		#ifdef SPECULAR_MAP
		/*
			const int colortex1Format = RGBA32F;
		*/
		#else
			#ifdef NORMAL_MAP
			/*
				const int colortex1Format = RGB32F;
			*/
			#else
			/*
				const int colortex1Format = RG32F;
			*/
			#endif
		#endif
	#else
		// Use the correct texture format for colortex1
		#ifdef SPECULAR_MAP
		/*
			const int colortex1Format = RGBA32UI;
		*/
		#else
			#ifdef NORMAL_MAP
			/*
				const int colortex1Format = RGB32UI;
			*/
			#else
			/*
				const int colortex1Format = RG32UI;
			*/
			#endif
		#endif
	#endif
#endif

