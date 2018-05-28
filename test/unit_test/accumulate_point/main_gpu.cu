//#ifndef GPU_KENERLS
//#define GPU_KERNELS
//#endif

#include <cassert>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>
#include <math_constants.h>
#include <float.h>
#include <string>
#include <vector>
#include <cuda.h>
#include <cuda_runtime.h>


#include "../../../g2g/common.h"
#include "../../../g2g/init.h"
#include "../../../g2g/cuda/cuda_extra.h"
#include "../../../g2g/matrix.h"
#include "../../../g2g/timer.h"
#include "../../../g2g/partition.h"
#include "../../../g2g/scalar_vector_types.h"
#include "../../../g2g/global_memory_pool.h"

//#include "../../../g2g/pointxc/calc_ggaCS.h"
//#include "../../../g2g/pointxc/calc_ggaOS.h"

//#include "../../../g2g/cuda/kernels/accumulate_point.h"

#include "../../../g2g/libxc/libxcproxy.h"
#include "../../../g2g/libxc/libxc_accumulate_point.h"
#include "test_input.h"

//////////////////////////////////////
//// CALC_GGA
#define POT_ALPHA     ((double)-0.738558766382022447)
#define POT_GL        ((double)0.620350490899400087)

#define POT_VOSKO_A1  ((double)0.03109205)
#define POT_VOSKO_B1  ((double)3.72744)
#define POT_VOSKO_C1  ((double)12.9352)
#define POT_VOSKO_X0  ((double)-0.10498)
#define POT_VOSKO_Q   ((double)6.15199066246304849)
#define POT_VOSKO_A16 ((double)0.005182008333)
#define POT_VOSKO_Q2  ((double)4.7309269)

#define POT_ALYP  ((double)0.04918)
#define POT_BLYP  ((double)0.132)
#define POT_CLYP  ((double)0.2533)
#define POT_CLYP3 ((double)0.0844333333)
#define POT_DLYP  ((double)0.349)
#define POT_DLYP3 ((double)0.116333333)
#define POT_CF    ((double)2.87123400018819)
#define POT_BETA  ((double)0.0042)

#define POT_ALF ((double)0.023266)
#define POT_BET ((double)7.389)
#define POT_GAM ((double)8.723)
#define POT_DEL ((double)0.472)

//////////////////////////////////////
//// UTILS

void set_array_values (double* data, double value,  int size) 
{
    if (data == NULL)
    {
	return;
    } else {
	for (int i=0; i<size; i++) {
	    data[i] = value;
	}
    }
}

//////////////////////////////////////
//// PRINT UTILS

void print_array (double* data, int size) 
{
    printf ("[");
    if (data == NULL) {
	printf("empty");
    } else {
	for (int i=0; i<size; i++) {
	    printf("%e,", data[i]);
	}
    }
    printf("]\n");
}

void print_array (float* data, int size) 
{
    printf ("[");
    if (data == NULL) {
	printf("empty");
    } else {
	for (int i=0; i<size; i++) {
	    printf("%e,", data[i]);
	}
    }
    printf("]\n");
}


void print_vec_type (G2G::vec_type<double,4>* data, int size) 
{
    printf ("[");
    if (data == NULL) {
	printf("empty");
    } else {
	for (int i=0; i<size; i++) {
	    printf("(%e,%e,%e),", data[i].x, data[i].y, data[i].z);
	}
    }
    printf("]\n");
}

void print_vec_type (G2G::vec_type<float,4>* data, int size) 
{
    printf ("[");
    if (data == NULL) {
	printf("empty");
    } else {
	for (int i=0; i<size; i++) {
	    printf("(%e,%e,%e),", data[i].x, data[i].y, data[i].z);
	}
    }
    printf("]\n");
}


void print_accumulate_point_data (G2G::vec_type<double,4>* dxyz, G2G::vec_type<double,4>* dd1, 
    G2G::vec_type<double,4>* dd2, double* energy, double* factor, double* point_weights,
    double* partial_density, int number_of_points)
{
    printf("=========\n");
    printf("= Data  =\n");
    printf("=========\n");
    printf("dxyz:"); print_vec_type(dxyz, number_of_points);
    printf("dd1:"); print_vec_type(dd1, number_of_points);
    printf("dd2:"); print_vec_type(dd2, number_of_points);
    printf("energy:"); print_array(energy, number_of_points);
    printf("factor:"); print_array(factor, number_of_points);
    printf("point_weights:"); print_array(point_weights, number_of_points);
    printf("partial_density:"); print_array(partial_density, number_of_points);
    printf("=========\n");

}

void print_accumulate_point_data (G2G::vec_type<float,4>* dxyz, G2G::vec_type<float,4>* dd1, 
    G2G::vec_type<float,4>* dd2, float* energy, float* factor, float* point_weights,
    float* partial_density, int number_of_points)
{
    printf("=========\n");
    printf("= Data  =\n");
    printf("=========\n");
    printf("dxyz:"); print_vec_type(dxyz, number_of_points);
    printf("dd1:"); print_vec_type(dd1, number_of_points);
    printf("dd2:"); print_vec_type(dd2, number_of_points);
    printf("energy:"); print_array(energy, number_of_points);
    printf("factor:"); print_array(factor, number_of_points);
    printf("point_weights:"); print_array(point_weights, number_of_points);
    printf("partial_density:"); print_array(partial_density, number_of_points);
    printf("=========\n");

}



//////////////////////////////////////
//// CALC_GGACS

template<class T, int iexch, unsigned int width>  __device__
void calc_ggaCS( T dens, 
                 const G2G::vec_type<T,width>& grad,
                 const G2G::vec_type<T,width>& hess1,
                 const G2G::vec_type<T,width>& hess2,
                 T& ex, 
                 T& ec, 
                 T& y2a)
{
   // hess1: xx, yy, zz  || hess2: xy, xz, yz
   const T MINIMUM_DENSITY_VALUE = 1e-13f;
   if (dens < MINIMUM_DENSITY_VALUE) { ex = ec = 0; return; }

   T y     = cbrt( (T)dens );  // rho^(1/3)
   T grad2 = grad.x * grad.x + grad.y * grad.y + grad.z * grad.z;
   if (grad2 == 0) grad2 = (T)FLT_MIN;
   T dgrad = sqrt(grad2);

   T d0 = hess1.x + hess1.y + hess1.z;
   T u0 = ((grad.x * grad.x) * hess1.x 
                  + 2.0 * grad.x * grad.y * hess2.x 
                  + 2.0 * grad.y * grad.z * hess2.z 
                  + 2.0 * grad.x * grad.z * hess2.y 
                  + (grad.y * grad.y) * hess1.y 
                  + (grad.z * grad.z) * hess1.z) / dgrad;
   y2a = 0;

   // Exchange - Perdew : Phys. Rev B 33 8800 (1986)
   if (iexch == 4 || iexch == 8) {
      T dens2 = (dens * dens);
      T ckf   = (T)3.0936677 * y;
      T s     = dgrad / ((T)2.0 * ckf * dens);

      T fx = (1.0 / 15.0);
      T s2 = (s * s);
      T s3 = (s * s * s);
      T g0 = 1.0 + 1.296 * s2 + 14.0 * pow(s, 4) + 0.2 * pow(s, 6);
      T F  = pow(g0, fx);
      T e  = POT_ALPHA * F * y;
      ex = e;

      T t = d0 / (dens * 4.0 * (ckf * ckf));
      T u = u0 / (pow( (T)2.0 * ckf, 3) * dens2);

      T g2  = 2.592 * s + 56.0 * s3 + 1.2 * pow(s, 5);
      T g3  = 2.592     + 56.0 * s2 + 1.2 * pow(s, 4);
      T g4  = 112.0 * s + 4.8  * s3;
      T dF  = fx * F/g0 * g2;
      T dsF = fx * F/g0 * (-14.0 * fx * g3 * g2/g0 + g4);

      y2a = POT_ALPHA * y * (1.33333333333 * F - t/s * dF - (u-1.3333333333 * s3) * dsF);
   } else if (iexch >= 5 && iexch <= 7) { // Becke  : Phys. Rev A 38 3098 (1988)
      T e0 = POT_ALPHA * y;
      T y2 = dens / 2.0;
      T r13 = cbrt( y2 );
      T r43 = cbrt( pow(y2, 4) );
      T Xs = dgrad / (2.0 * r43);
      T siper = asinh(Xs);
      T DN = 1.0 + 6.0 * POT_BETA * Xs * siper;
      T ect = -2.0 * POT_BETA * r43 * Xs * Xs/(DN * dens);
      T e = e0 + ect;
      ex = e;

      // Potential
      T v0 = 1.33333333333333 * e0;
      T Fb = 1.0 / DN;
      T XA1 = Xs / sqrt(1.0 + Xs * Xs);
      T DN1 = 1.0 + Fb * (1.0 - 6.0 * POT_BETA * Xs * XA1);
      T DN2 = 1.0 / (1.0 + Xs * Xs) + 2.0 * Fb * (2.0 - 6.0 * POT_BETA * Xs * XA1);
      T DN3 = siper * (1.0 + 2.0 * Fb) + XA1 * DN2;
      T D02 = d0 / 2.0;
      T de1 = 1.33333333333333 / (cbrt(pow((T)dens,7) ) );

      T DGRADx = (grad.x * hess1.x + grad.y * hess2.x + grad.z * hess2.y) / dgrad;
      T GRADXx = cbrt( (T) 2.0 ) * (1.0 / (dens * y) * DGRADx - de1 * grad.x * dgrad);
      T DGRADy = (grad.x * hess2.x + grad.y * hess1.y + grad.z * hess2.z) / dgrad;
      T GRADXy = cbrt( (T) 2.0 ) * (1.0 / (dens * y) * DGRADy - de1 * grad.y * dgrad);
      T DGRADz = (grad.x * hess2.y + grad.y * hess2.z + grad.z * hess1.z) / dgrad;
      T GRADXz = cbrt( (T) 2.0 ) * (1.0 / (dens * y) * DGRADz - de1 * grad.z * dgrad);

      T T1   = grad.x / 2.0 * GRADXx;
      T T2   = grad.y / 2.0 * GRADXy;
      T T3   = grad.z / 2.0 * GRADXz;
      T DN4  = 6.0 * POT_BETA * Fb * (T1 + T2 + T3);
      T DN5  = 1.33333333333333 * r43 * r13 * Xs * Xs;
      T TOT2 = DN5 - D02 * DN1 + DN4 * DN3;

      T vxc = -POT_BETA * Fb/r43 * TOT2;
      y2a = v0 + vxc;
   } else { // PBE
      //T dgrad2 = grad.y * grad.y * hess1.y;
      //T dgrad3 = grad.z * grad.z * hess1.z;
      //T dgrad4 = grad.x * grad.y * hess2.x;
      //T dgrad5 = grad.x * grad.z * hess2.y;
      //T dgrad6 = grad.y * grad.z * hess2.z;
      //T delgrad = (dgrad1 + dgrad2 + dgrad3 + 2 * (dgrad4 + dgrad5 + dgrad6)) / dgrad;
      //T rlap = hess1.x + hess1.y + hess1.z;

      //T expbe, vxpbe, ecpbe, vcpbe;
      //pbeCS(dens, dgrad, delgrad, rlap, expbe, vxpbe, ecpbe, vcpbe);

      //ex  = expbe;
      //ec  = ecpbe;
      //y2a = vxpbe + vcpbe;
      return;
   }

   // Correlation - Perdew : Phys. Rev B 33 8822 (1986)
   if (iexch >= 4 && iexch <= 6) {
      // TO-DO: hay algun problema con 4 y 5, probablemente este aca
      T dens2 = (dens * dens);
      T rs  = POT_GL / y;
      T x1  = sqrt(rs);
      T Xx  = rs + POT_VOSKO_B1 * x1 + POT_VOSKO_C1;
      T Xxo = (POT_VOSKO_X0 * POT_VOSKO_X0) 
                      + POT_VOSKO_B1 * POT_VOSKO_X0 + POT_VOSKO_C1;
  
      T t1 = 2.0 * x1 + POT_VOSKO_B1;
      T t2 = log(Xx);
      T t3 = atan(POT_VOSKO_Q/t1);
      T t4 = POT_VOSKO_B1 * POT_VOSKO_X0/Xxo;

      ec = POT_VOSKO_A1 * ( 2.0 * log(x1) - t2 
           + 2.0 * POT_VOSKO_B1/POT_VOSKO_Q * t3
           - t4 *(2.0 * log(x1 - POT_VOSKO_X0) - t2 
           + 2.0 * (POT_VOSKO_B1 + 2.0 * POT_VOSKO_X0) / POT_VOSKO_Q * t3));

      T t5 = (POT_VOSKO_B1 * x1 + 2.0 * POT_VOSKO_C1) / x1;
      T t6 = POT_VOSKO_X0 / Xxo;
      T vc = ec - POT_VOSKO_A16 * x1 * 
                   ( t5/Xx - 4.0 * POT_VOSKO_B1 / ((t1 * t1)+(POT_VOSKO_Q * POT_VOSKO_Q2)) 
                   * (1.0 - t6 * (POT_VOSKO_B1 - 2.0 * POT_VOSKO_X0)) 
                   - t4 * (2.0 / (x1 - POT_VOSKO_X0) - t1/Xx));

      if (iexch == 6) {
         y2a = y2a + vc;
      } else {
         T rs2 = (rs * rs);
         T Cx1 = 0.002568f + POT_ALF * rs + POT_BET * rs2;
         T Cx2 = 1.0f + POT_GAM * rs + POT_DEL * rs2 + 1.0e4 * POT_BET * (rs * rs * rs);
         T C   = 0.001667 + Cx1/Cx2;
         T Cx3 = POT_ALF + 2.0f * POT_BET * rs;
         T Cx4 = POT_GAM + 2.0f * POT_DEL * rs + 3.0e4 * POT_BET * rs2;
         T dC  = Cx3/Cx2 - Cx1/(Cx2 * Cx2) * Cx4;
         dC = -0.333333333333333f * dC * POT_GL / (y * dens);

         T phi  = 0.0008129082f/C * dgrad/pow((T)dens, (T)(7.0f/6.0f));
         T expo = exp(-phi);
         T ex0  = expo * C;

         ec = ec + ex0 * grad2 / (y * dens2);

         T D1   = (2.0f - phi) * d0/dens;
         T phi2 = (phi * phi);
         T D2   = 1.33333333333333333f - 3.666666666666666666f * phi + 1.166666666666666f * phi2;
         D2 = D2 * grad2/dens2;
         T D3 = phi * (phi - 3.0f) * u0/(dens * dgrad);
         T D4 = expo * grad2 / (y * dens) * (phi2 - phi - 1.0f) * dC;

         vc = vc - 1.0 * (ex0 / y * (D1 - D2 + D3) - D4);
         y2a = y2a + vc;
      }
   } else if (iexch == 7 || iexch == 8) { // Correlation - LYP: PRB 37 785 (1988)
      T rom13 = 1 / cbrt( dens );
      T rom53 = cbrt( pow(dens, 5) );
      T ecro  = expf(-POT_CLYP * rom13);
      T f1    = 1.0f / (1.0f + POT_DLYP * rom13);
      T tw    = 1.0f / 8.0f * (grad2/dens - d0);
      T term  = (tw / 9.0f + d0 / 18.0f) - 2.0f * tw + POT_CF * rom53;
      term = dens + POT_BLYP * (rom13 * rom13) * ecro * term;

      ec = -POT_ALYP * f1 * term/dens;

      T h1 = ecro/rom53;
      T g1 = f1 * h1;
      T tm1 = POT_DLYP3 * (rom13/dens);
      T fp1 = tm1 * (f1 * f1);
      T tm2 = -1.666666666f + POT_CLYP3 * rom13;
      T hp1 = h1 * tm2/dens;
      T gp1 = fp1 * h1 + hp1 * f1;
      T fp2 = tm1 * 2.0f * f1 * (fp1 - 0.6666666666f * f1/dens);
      T tm3 = 1.6666666666f - POT_CLYP3 * 1.3333333333f * rom13;
      T hp2 = hp1 * tm2/dens + h1 * tm3/(dens * dens);
      T gp2 = fp2 * h1 + 2.0f * fp1 * hp1 + hp2 * f1;

      T term3 = -POT_ALYP * (fp1 * dens + f1) 
                          -POT_ALYP * POT_BLYP * POT_CF * (gp1 * dens + 8.0f/3.0f * g1) * rom53;
      T term4 = (gp2 * dens * grad2 + gp1 * (3.0f * grad2 + 2.0f * dens * d0)
                          + 4.0f * g1 * d0) * POT_ALYP * POT_BLYP/4.0f;
      T term5 = (3.0f * gp2 * dens * grad2 + gp1 * (5.0f * grad2 + 6.0f * dens * d0)
                          + 4.0f * g1 * d0) * POT_ALYP * POT_BLYP/72.0f;

      y2a = y2a + (term3 - term4 - term5);
   }
}

template<class T, unsigned int width> __device__
void calc_ggaCS_in( T dens, 
                    const G2G::vec_type<T,width>& grad,
                    const G2G::vec_type<T,width>& hess1,
                    const G2G::vec_type<T,width>& hess2,
                    T& ex, 
                    T& ec, 
                    T& y2a,
                    const int iexch)
{
   switch(iexch) {
      case 0: return calc_ggaCS<T, 0, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 1: return calc_ggaCS<T, 1, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 2: return calc_ggaCS<T, 2, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 3: return calc_ggaCS<T, 3, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 4: return calc_ggaCS<T, 4, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 5: return calc_ggaCS<T, 5, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 6: return calc_ggaCS<T, 6, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 7: return calc_ggaCS<T, 7, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 8: return calc_ggaCS<T, 8, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      case 9: return calc_ggaCS<T, 9, width>(dens, grad, hess1, hess2, ex, ec, y2a);
      default: assert(false);
   }
}



//////////////////////////////////////
//// KERNEL FOR ACCUMULATE_POINT

template<class T, bool compute_energy, bool compute_factor, bool lda>
__global__ void gpu_accumulate_point (T* const energy, T* const factor, 
		    const T* const point_weights,
            	    uint points, int block_height, T* partial_density, 
		    G2G::vec_type<T,4>* dxyz,
                    G2G::vec_type<T,4>* dd1, 
		    G2G::vec_type<T,4>* dd2) {

  uint point = blockIdx.x * DENSITY_ACCUM_BLOCK_SIZE + threadIdx.x;
  //uint point = blockIdx.x * 128 + threadIdx.x;

  T point_weight = 0.0f;
  T y2a, exc_corr, exc_c, exc_x;

  T _partial_density(0.0f);
  G2G::vec_type<T,4> _dxyz, _dd1, _dd2;

  _dxyz = _dd1 = _dd2 = G2G::vec_type<T,4>(0.0f,0.0f,0.0f,0.0f);

  bool valid_thread = (point < points);
  if (valid_thread)
    point_weight = point_weights[point];

  if (valid_thread) {
    for(int j =0 ; j<block_height; j++) {
      const int this_row = j*points+point;

      _partial_density += partial_density[this_row];
      _dxyz += dxyz[this_row];
      _dd1 += dd1[this_row];
      _dd2 += dd2[this_row];
     }
  }

  calc_ggaCS_in<T, 4>(_partial_density, _dxyz, _dd1, _dd2, exc_x, exc_c, y2a, 9);
  exc_corr = exc_x + exc_c;

  if (compute_energy && valid_thread){
    energy[point] = (_partial_density * point_weight) * exc_corr;
  }

  if (compute_factor && valid_thread){
    factor[point] = point_weight * y2a;
  }

}


//////////////////////////////////////
//// TESTS

void gpu_accumulate_point_test0001()
{
    printf("** gpu_accumulate_point_test0001 **\n");

    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu;

    dxyz_gpu.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *energy_gpu = NULL;
    double *factor_gpu = NULL;
    double *point_weights_gpu = NULL;
    double *partial_density_gpu = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);
    err = cudaMalloc((void**)&energy_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    err = cudaMalloc((void**)&point_weights_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(energy_gpu, 0, size);
    cudaMemset(factor_gpu, 0, size);
    cudaMemset(point_weights_gpu, 1, size);
    cudaMemset(partial_density_gpu, 1, size);

    // Launch the CUDA Kernel
    int numElements = n+m;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
    // Call the CUDA KERNEL
    gpu_accumulate_point<double,true, true, false><<<blocksPerGrid, threadsPerBlock>>> 
		    (energy_gpu, factor_gpu, 
		    point_weights_gpu,
            	    numElements, 1, partial_density_gpu, 
		    dxyz_gpu.data,
                    dd1_gpu.data, 
		    dd2_gpu.data);


    // Allocate the host input vectors
    double *energy_cpu = (double *)malloc(size);
    double *factor_cpu = (double *)malloc(size);
    double *point_weights_cpu = (double *)malloc(size);
    double *partial_density_cpu = (double *)malloc(size);

    // Copy the vectors from gpu to cpu
    // Be aware that energy_gpu can be NULL.
    err = cudaMemcpy(energy_cpu, energy_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector energy_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(factor_cpu, factor_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector factor_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(point_weights_cpu, point_weights_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector point_weights_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(partial_density_cpu, partial_density_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector partial_density_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    // Before print the results, get the data from cuda
    G2G::vec_type<double,4>* dxyz_cpu;
    G2G::vec_type<double,4>* dd1_cpu;
    G2G::vec_type<double,4>* dd2_cpu;

    // Alloc memory in the host for the gpu data
    uint cpu_vecs_size = number_of_points * sizeof(G2G::vec_type<double,4>);
    dxyz_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd1_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd2_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);

    // Copy data from device to host.
    err = cudaMemcpy(dxyz_cpu, dxyz_gpu.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dxyz_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd1_cpu, dd1_gpu.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd1_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd2_cpu, dd2_gpu.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd2_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (dxyz_cpu, dd1_cpu, dd2_cpu, energy_cpu, 
	factor_cpu, point_weights_cpu, 
	partial_density_cpu, number_of_points);

    free(energy_cpu);
    free(factor_cpu);
    free(point_weights_cpu);
    free(partial_density_cpu);

    free(dxyz_cpu);
    free(dd1_cpu);
    free(dd2_cpu);

    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(point_weights_gpu);
    cudaFree(partial_density_gpu);

}

void accumulate_data_for_libxc_test0001()
{
    printf("** accumulate_data_for_libxc_test0001 **\n");

    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *partial_density_gpu_accum = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);
    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_accum, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(point_weights_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_accum, 1, size);

    // Launch the CUDA Kernel
    int numElements = n+m;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);

    // Call the CUDA KERNEL
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid,threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	partial_density_gpu_accum, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // Free memory
    cudaFree (point_weights_gpu_in);
    cudaFree (partial_density_gpu_in);
    cudaFree (partial_density_gpu_accum);

}


void accumulate_data_for_libxc_test0002()
{
    printf("** accumulate_data_for_libxc_test0002 **\n");

    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *partial_density_gpu_accum = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);
    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_accum, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(point_weights_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_accum, 1, size);

    // Launch the CUDA Kernel
    int numElements = n+m;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);

    // Call the CUDA KERNEL
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid,threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	partial_density_gpu_accum, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // With the accumulate parameters we can use
    // the data for libxc.
    G2G::vec_type<double,4>* dxyz_cpu;
    G2G::vec_type<double,4>* dd1_cpu;
    G2G::vec_type<double,4>* dd2_cpu;

    // Alloc memory in the host for the gpu data
    uint cpu_vecs_size = number_of_points * sizeof(G2G::vec_type<double,4>);
    dxyz_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd1_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd2_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);

    // Copy data from device to host.
    err = cudaMemcpy(dxyz_cpu, dxyz_gpu_accum.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dxyz_gpu_accum from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd1_cpu, dd1_gpu_accum.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd1_gpu_accum from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd2_cpu, dd2_gpu_accum.data, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd2_gpu_accum from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (dxyz_cpu, dd1_cpu, dd2_cpu, NULL, 
	NULL, NULL, NULL, number_of_points);

    // Free memory
    free(dxyz_cpu);
    free(dd1_cpu);
    free(dd2_cpu);

    cudaFree (point_weights_gpu_in);
    cudaFree (partial_density_gpu_in);
    cudaFree (partial_density_gpu_accum);

}


void accumulate_data_for_libxc_test0003()
{
    printf("** accumulate_data_for_libxc_test0003 **\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *accumulated_density_gpu = NULL;

    // Now the arrays for energy, factors, point_weight and partial_density
    double *energy_gpu_in = NULL;
    double *factor_gpu_in = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);

    err = cudaMalloc((void**)&energy_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&accumulated_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(energy_gpu_in, 0, size);
    cudaMemset(factor_gpu_in, 0, size);
    cudaMemset(point_weights_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_in, 1, size);
    cudaMemset(accumulated_density_gpu, 1, size);

    // Launch the CUDA Kernel
    int numElements = number_of_points;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);

    // Call the CUDA KERNEL
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid,threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	accumulated_density_gpu, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 101;
    const int functionalCorrelation = 130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    // Calculate exc_corr and y2a
    libxc_exchange_correlation_cpu<double, true, true, false> (&libxcProxy,
	energy_gpu_in,
	factor_gpu_in,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu_accum.data,
        dd1_gpu_accum.data,
	dd2_gpu_accum.data);

    // TODO: queda unir los resultados.
    // con la funcion gpu_accumulate_energy_and_factor_from_libxc(...);

    // Free memory
    cudaFree(energy_gpu_in);
    cudaFree(factor_gpu_in);
    cudaFree(point_weights_gpu_in);
    cudaFree(partial_density_gpu_in);
    cudaFree(accumulated_density_gpu);
#endif
}


void accumulate_data_for_libxc_test0004()
{
    printf("** accumulate_data_for_libxc_test0004 **\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *accumulated_density_gpu = NULL;

    // Now the arrays for energy, factors, point_weight and partial_density
    double *energy_gpu_in = NULL;
    double *factor_gpu_in = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);

    err = cudaMalloc((void**)&energy_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&accumulated_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(energy_gpu_in, 0, size);
    cudaMemset(factor_gpu_in, 0, size);
    cudaMemset(point_weights_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_in, 1, size);
    cudaMemset(accumulated_density_gpu, 1, size);

    // Launch the CUDA Kernel
    int numElements = number_of_points;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);

    // Call the CUDA KERNEL
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid, threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	accumulated_density_gpu, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 101;
    const int functionalCorrelation = 130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    // Calculate exc_corr and y2a
    libxc_exchange_correlation_cpu<double, true, true, false> (&libxcProxy,
	energy_gpu_in,
	factor_gpu_in,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu_accum.data,
        dd1_gpu_accum.data,
	dd2_gpu_accum.data);

    // Join the results.
    gpu_accumulate_energy_and_forces_from_libxc<double, true, true, false><<<blocksPerGrid, threadsPerBlock>>> (
	energy_gpu_in,
	factor_gpu_in,
	point_weights_gpu_in,
	number_of_points,
	accumulated_density_gpu);

    // Free memory
    cudaFree(energy_gpu_in);
    cudaFree(factor_gpu_in);
    cudaFree(point_weights_gpu_in);
    cudaFree(partial_density_gpu_in);
    cudaFree(accumulated_density_gpu);
#endif
}

void accumulate_data_for_libxc_test0005()
{
    printf("** accumulate_data_for_libxc_test0005 **\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu = NULL;
    double *partial_density_gpu = NULL;
    // Accum
    double *accumulated_density_gpu = NULL;

    // Now the arrays for energy, factors, point_weight and partial_density
    double *energy_gpu = NULL;
    double *factor_gpu = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);

    err = cudaMalloc((void**)&energy_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    err = cudaMalloc((void**)&point_weights_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu!\n");
    }

    err = cudaMalloc((void**)&accumulated_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(energy_gpu, 0, size);
    cudaMemset(factor_gpu, 0, size);
    cudaMemset(point_weights_gpu, 1, size);
    cudaMemset(partial_density_gpu, 1, size);
    cudaMemset(accumulated_density_gpu, 1, size);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    ///////////////////////////////////////////////////
    // Calculate exc_corr and y2a using LIBXC GPU
    libxc_exchange_correlation_gpu<double, true, true, false> (&libxcProxy,
	energy_gpu,
	factor_gpu,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu_accum.data,
        dd1_gpu_accum.data,
	dd2_gpu_accum.data);

    ///////////////////////////////////////////////////
    // Check and print the results.
    // Copy back the results before print.
    // Allocate the host input vectors
    double *energy_cpu = (double *)malloc(size);
    double *factor_cpu = (double *)malloc(size);
    double *point_weights_cpu = (double *)malloc(size);
    double *partial_density_cpu = (double *)malloc(size);

    // Copy the vectors from gpu to cpu
    // Be aware that energy_gpu can be NULL.
    err = cudaMemcpy(energy_cpu, energy_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector energy_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(factor_cpu, factor_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector factor_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(point_weights_cpu, point_weights_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector point_weights_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(partial_density_cpu, partial_density_gpu, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector partial_density_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    // Before print the results, get the data from cuda
    G2G::vec_type<double,4>* dxyz_cpu;
    G2G::vec_type<double,4>* dd1_cpu;
    G2G::vec_type<double,4>* dd2_cpu;

    // Alloc memory in the host for the gpu data
    uint cpu_vecs_size = number_of_points * sizeof(G2G::vec_type<double,4>);
    dxyz_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd1_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd2_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);

    // Copy data from device to host.
    err = cudaMemcpy(dxyz_cpu, dxyz_gpu.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dxyz_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd1_cpu, dd1_gpu.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd1_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd2_cpu, dd2_gpu.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd2_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (dxyz_cpu, dd1_cpu, dd2_cpu, energy_cpu, 
	factor_cpu, NULL, NULL, number_of_points);

    free(energy_cpu);
    free(factor_cpu);
    free(point_weights_cpu);
    free(partial_density_cpu);

    free(dxyz_cpu);
    free(dd1_cpu);
    free(dd2_cpu);

    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(point_weights_gpu);
    cudaFree(partial_density_gpu);


    // Free memory
    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(point_weights_gpu);
    cudaFree(partial_density_gpu);
    cudaFree(accumulated_density_gpu);
#endif
}

void accumulate_data_for_libxc_test0006()
{
    printf("** accumulate_data_for_libxc_test0006() **\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in;

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum;
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum;

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *accumulated_density_gpu = NULL;

    // Now the arrays for energy, factors, point_weight and partial_density
    double *energy_gpu_in = NULL;
    double *factor_gpu_in = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);

    err = cudaMalloc((void**)&energy_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&accumulated_density_gpu, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Set the cuda array values to a default value.
    cudaMemset(energy_gpu_in, 0, size);
    cudaMemset(factor_gpu_in, 0, size);
    cudaMemset(point_weights_gpu_in, 1, size);
    cudaMemset(partial_density_gpu_in, 1, size);
    cudaMemset(accumulated_density_gpu, 1, size);

    // Launch the CUDA Kernel
    int numElements = number_of_points;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);

    //////////////////////////////////////////////
    // Call the CUDA KERNEL for accumulate point
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid, threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	accumulated_density_gpu, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    //////////////////////////////////////////////////
    // Calculate exc_corr and y2a in GPU with LIBXC
    libxc_exchange_correlation_gpu<double, true, true, false> (&libxcProxy,
	energy_gpu_in,
	factor_gpu_in,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu_accum.data,
        dd1_gpu_accum.data,
	dd2_gpu_accum.data);


    ////////////////////////////////
    // Join the results for LIO
    gpu_accumulate_energy_and_forces_from_libxc<double, true, true, false><<<blocksPerGrid, threadsPerBlock>>> (
	energy_gpu_in,
	factor_gpu_in,
	point_weights_gpu_in,
	number_of_points,
	accumulated_density_gpu);

    ///////////////////////////////////////
    // Check and print the results.
    // Copy back the results before print.
    // Allocate the host input vectors
    double *energy_cpu = (double *)malloc(size);
    double *factor_cpu = (double *)malloc(size);
    double *point_weights_cpu = (double *)malloc(size);
    double *partial_density_cpu = (double *)malloc(size);

    // Copy the vectors from gpu to cpu
    // Be aware that energy_gpu can be NULL.
    err = cudaMemcpy(energy_cpu, energy_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector energy_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(factor_cpu, factor_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector factor_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(point_weights_cpu, point_weights_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector point_weights_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(partial_density_cpu, partial_density_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector partial_density_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    // Before print the results, get the data from cuda
    G2G::vec_type<double,4>* dxyz_cpu;
    G2G::vec_type<double,4>* dd1_cpu;
    G2G::vec_type<double,4>* dd2_cpu;

    // Alloc memory in the host for the gpu data
    uint cpu_vecs_size = number_of_points * sizeof(G2G::vec_type<double,4>);
    dxyz_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd1_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);
    dd2_cpu = (G2G::vec_type<double,4> *)malloc(cpu_vecs_size);

    // Copy data from device to host.
    err = cudaMemcpy(dxyz_cpu, dxyz_gpu_in.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dxyz_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd1_cpu, dd1_gpu_in.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd1_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(dd2_cpu, dd2_gpu_in.data, cpu_vecs_size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector dd2_gpu from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (dxyz_cpu, dd1_cpu, dd2_cpu, energy_cpu, 
	factor_cpu, point_weights_cpu, 
	partial_density_cpu, number_of_points);

    ////////////////////////////
    // Free Memory
    free(energy_cpu);
    free(factor_cpu);
    free(point_weights_cpu);
    free(partial_density_cpu);

    free(dxyz_cpu);
    free(dd1_cpu);
    free(dd2_cpu);

    cudaFree(energy_gpu_in);
    cudaFree(factor_gpu_in);
    cudaFree(point_weights_gpu_in);
    cudaFree(partial_density_gpu_in);
    cudaFree(accumulated_density_gpu);
#endif
}


///////////////////////////////////////////////////
// Cuda Matrix Helpers
G2G::HostMatrix< G2G::vec_type<double,4> > createMatrix(int size)
{
    //typedef G2G::vec_type<float,4> vec_type4;
    //G2G::CudaMatrix<T> function_values;
    //G2G::CudaMatrix<vec_type4> gradient_values;
    //G2G::CudaMatrix<vec_type4> hessian_values_transposed;

    //G2G::CudaMatrix< G2G::vec_type<double,4> > aCudaMatrix;
    G2G::HostMatrix< G2G::vec_type<double,4> > aHostMatrix(size, 1);

    //G2G::vec_type<float,4> one(1,1,1,1);
    G2G::vec_type<float,4> zero(0,0,0,0);

    for (int i=0; i<5; i++){
	aHostMatrix(i).x = zero.x;
	aHostMatrix(i).y = zero.y;
	aHostMatrix(i).z = zero.z;
    }

    //aCudaMatrix = aHostMatrix;
    return aHostMatrix;
}


/////////////////////////////////////////////////
//
void accumulate_data_for_libxc_test0007() {
    printf("accumulate_data_for_libxc_test0007()\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in = createMatrix(number_of_points);

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum = createMatrix(number_of_points);

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *partial_density_gpu_accum = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);
    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_accum, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Now the arrays for energy, factors
    double *energy_gpu_in = NULL;
    double *factor_gpu_in = NULL;
    err = cudaMalloc((void**)&energy_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    // Launch the CUDA Kernel
    int numElements = n+m;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    ///////////////////////
    // Set data
    //=========
    //= Data  =
    //=========
    //number_of_points:221
    //block_height:1
    //double dxyz[221] = {(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000001,-0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000001,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000001,0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000035,-0.000017,0.000026),(0.000009,0.000001,0.000028),(0.000013,0.000007,0.000010),(0.000003,0.000003,0.000001),(0.000002,0.000004,0.000005),(-0.000000,0.000017,-0.000003),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000008,0.000000,0.000008),(0.000002,0.000004,0.000002),(0.000007,-0.000007,0.000007),(0.000002,0.000005,0.000004),(0.000005,-0.000005,0.000009),(0.000005,-0.000009,0.000005),(0.000004,0.000004,0.000002),(0.000009,-0.000005,0.000005),(0.000002,0.000004,0.000007),(0.000003,-0.000003,0.000011),(0.000003,-0.000011,0.000003),(0.000006,0.000004,0.000001),(0.000010,-0.000003,0.000003),(0.000008,-0.000008,0.000004),(0.000005,0.000004,0.000005),(0.000008,-0.000004,0.000008),(0.000004,-0.000008,0.000008),(0.000010,0.000001,0.000003),(0.000003,0.000001,0.000010),(0.000009,-0.000001,0.000006),(0.000008,0.000002,0.000005),(0.000006,-0.000002,0.000010),(0.000005,0.000002,0.000008),(0.000025,0.000007,0.000024),(0.000003,0.000011,0.000002),(0.000026,-0.000025,0.000025),(0.000001,0.000019,0.000006),(0.000019,-0.000018,0.000034),(0.000055,-0.000034,0.000067),(0.000019,-0.000035,0.000019),(0.000007,0.000017,-0.000000),(0.000034,-0.000017,0.000018),(0.000001,0.000018,0.000015),(0.000010,-0.000008,0.000037),(0.000011,-0.000039,0.000010),(0.000013,0.000017,-0.000002),(0.000036,-0.000007,0.000008),(0.000025,-0.000013,0.000025),(0.000030,-0.000028,0.000012),(0.000012,0.000019,0.000010),(0.000029,-0.000010,0.000028),(0.000011,-0.000005,0.000017),(0.000013,-0.000029,0.000030),(0.000029,0.000008,0.000006),(0.000009,0.000007,0.000031),(0.000033,-0.000001,0.000018),(0.000022,0.000014,0.000010),(0.000020,-0.000002,0.000033),(0.000013,0.000014,0.000023),(0.000031,0.000025,0.000028),(-0.000001,0.000014,-0.000001),(0.000040,-0.000035,0.000037),(-0.000007,0.000036,-0.000002),(0.000026,-0.000020,0.000053),(0.000077,-0.000088,0.000098),(0.000028,-0.000053,0.000025),(0.000001,0.000031,-0.000009),(0.000053,-0.000018,0.000021),(0.000007,0.000042,0.000003),(0.000043,-0.000007,0.000040),(0.000036,0.000028,-0.000003),(0.000004,0.000027,0.000039),(0.000047,0.000011,0.000020),(0.000024,0.000037,0.000004),(0.000025,0.000010,0.000046),(0.000010,0.000037,0.000023),(0.000027,0.000054,0.000019),(-0.000008,0.000019,-0.000007),(0.000041,-0.000028,0.000034),(-0.000018,0.000055,-0.000013),(0.000021,-0.000008,0.000054),(0.000066,-0.000120,0.000090),(0.000024,-0.000052,0.000017),(-0.000008,0.000046,-0.000019),(0.000057,-0.000004,0.000011),(-0.000003,0.000069,-0.000010),(0.000044,0.000011,0.000037),(0.000048,0.000036,0.000009),(0.000018,0.000066,-0.000011),(0.000019,0.000034,0.000044),(-0.000001,0.000067,0.000014),(0.000023,0.000084,0.000011),(-0.000016,0.000035,-0.000016),(0.000037,-0.000014,0.000026),(-0.000009,0.000097,-0.000018),(0.000042,0.000035,0.000030),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000009,-0.000018,0.000016),(0.000005,0.000007,0.000001),(0.000011,0.000005,0.000018)};
    //double dd1[221] = {(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000001,0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000002,0.000000),(0.000001,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000000,0.000001,0.000001),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000014,-0.000019,-0.000005),(-0.000011,-0.000016,0.000027),(0.000007,-0.000005,0.000001),(0.000003,0.000002,-0.000002),(-0.000002,0.000002,0.000003),(-0.000004,0.000095,0.000018),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,-0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000001),(-0.000000,-0.000000,0.000001),(-0.000000,0.000001,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,0.000000),(0.000000,-0.000000,0.000001),(0.000001,-0.000000,0.000000),(0.000001,-0.000000,0.000000),(0.000001,0.000000,-0.000000),(-0.000000,0.000001,0.000000),(-0.000000,0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000001,-0.000000),(0.000007,-0.000004,0.000007),(-0.000000,0.000006,-0.000000),(0.000005,0.000004,0.000004),(-0.000002,0.000003,0.000002),(0.000001,0.000001,0.000011),(0.000001,0.000011,0.000001),(0.000002,0.000003,-0.000002),(0.000011,0.000001,0.000001),(-0.000002,-0.000000,0.000008),(-0.000002,-0.000002,0.000016),(-0.000002,0.000016,-0.000002),(0.000007,0.000000,-0.000003),(0.000016,-0.000002,-0.000002),(0.000007,0.000007,-0.000001),(0.000003,0.000000,0.000002),(0.000007,-0.000002,0.000007),(-0.000001,0.000007,0.000007),(0.000014,-0.000004,-0.000002),(-0.000001,-0.000004,0.000015),(0.000013,-0.000003,0.000002),(0.000009,-0.000002,0.000001),(0.000003,-0.000003,0.000013),(0.000001,-0.000003,0.000009),(0.000006,-0.000021,0.000003),(-0.000001,0.000033,0.000004),(0.000003,-0.000001,0.000001),(-0.000012,0.000018,-0.000012),(-0.000009,-0.000012,0.000021),(0.000108,0.000012,0.000166),(-0.000008,0.000020,-0.000010),(-0.000008,0.000020,-0.000010),(0.000022,-0.000013,-0.000011),(-0.000016,0.000001,-0.000004),(-0.000017,-0.000021,0.000032),(-0.000017,0.000034,-0.000019),(-0.000002,0.000006,-0.000014),(0.000031,-0.000021,-0.000019),(0.000058,0.000034,0.000070),(0.000011,0.000006,-0.000017),(-0.000008,0.000002,-0.000012),(0.000010,-0.000019,0.000007),(0.000028,0.000035,0.000056),(-0.000016,0.000008,0.000010),(0.000021,-0.000019,-0.000019),(-0.000016,-0.000021,0.000022),(0.000023,-0.000023,-0.000008),(0.000007,-0.000011,-0.000014),(-0.000005,-0.000023,0.000021),(-0.000010,-0.000013,0.000005),(-0.000018,-0.000049,-0.000029),(0.000003,0.000100,0.000020),(-0.000023,-0.000037,-0.000030),(-0.000023,0.000058,-0.000029),(-0.000041,-0.000054,0.000001),(0.000149,0.000116,0.000241),(-0.000040,-0.000004,-0.000046),(-0.000022,0.000066,-0.000011),(0.000008,-0.000054,-0.000048),(-0.000032,0.000016,-0.000039),(-0.000012,-0.000062,-0.000021),(0.000003,-0.000041,-0.000050),(-0.000046,-0.000047,-0.000002),(0.000007,-0.000061,-0.000044),(-0.000016,-0.000018,-0.000045),(-0.000035,-0.000062,-0.000001),(-0.000038,-0.000023,-0.000025),(-0.000040,-0.000078,-0.000057),(0.000006,0.000207,0.000035),(-0.000058,-0.000088,-0.000072),(-0.000028,0.000128,-0.000030),(-0.000083,-0.000109,-0.000022),(0.000146,0.000282,0.000245),(-0.000084,-0.000038,-0.000096),(-0.000027,0.000142,-0.000004),(-0.000007,-0.000109,-0.000095),(-0.000047,0.000050,-0.000053),(-0.000038,-0.000118,-0.000055),(-0.000003,-0.000105,-0.000083),(-0.000026,-0.000015,-0.000070),(-0.000070,-0.000109,-0.000020),(-0.000064,-0.000024,-0.000042),(-0.000057,-0.000111,-0.000077),(-0.000002,0.000337,0.000033),(-0.000100,-0.000144,-0.000121),(-0.000057,0.000094,-0.000062),(-0.000065,-0.000183,-0.000088),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000004,0.000013,0.000007),(0.000001,0.000011,-0.000001),(-0.000000,-0.000009,0.000014)};
    //double dd2[221] = {(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000001,0.000001,-0.000001),(-0.000000,0.000001,-0.000000),(-0.000001,0.000000,-0.000001),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000017,0.000027,-0.000011),(0.000003,0.000011,0.000005),(0.000010,0.000011,0.000009),(0.000005,0.000000,0.000001),(0.000003,0.000002,0.000007),(-0.000028,0.000011,-0.000050),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000001,0.000010,0.000001),(0.000002,0.000001,0.000002),(-0.000008,0.000008,-0.000008),(0.000003,0.000002,0.000006),(-0.000005,0.000008,-0.000008),(-0.000008,0.000005,-0.000008),(0.000006,0.000001,0.000003),(-0.000008,0.000008,-0.000004),(0.000002,0.000002,0.000007),(-0.000002,0.000006,-0.000006),(-0.000006,0.000002,-0.000006),(0.000007,0.000001,0.000002),(-0.000005,0.000005,-0.000001),(-0.000011,0.000005,-0.000005),(0.000005,0.000005,0.000005),(-0.000005,0.000011,-0.000005),(-0.000005,0.000005,-0.000011),(0.000002,0.000005,0.000001),(0.000001,0.000006,0.000002),(-0.000002,0.000010,-0.000001),(0.000005,0.000007,0.000003),(-0.000001,0.000010,-0.000002),(0.000003,0.000008,0.000004),(0.000011,0.000022,0.000012),(-0.000008,0.000006,-0.000012),(-0.000021,0.000022,-0.000020),(0.000007,-0.000005,0.000015),(-0.000010,0.000022,-0.000020),(-0.000080,0.000147,-0.000094),(-0.000022,0.000011,-0.000021),(0.000013,-0.000005,0.000001),(-0.000019,0.000020,-0.000008),(0.000007,-0.000006,0.000026),(-0.000000,0.000012,-0.000008),(-0.000013,0.000002,-0.000012),(0.000022,-0.000008,0.000003),(-0.000006,0.000008,0.000002),(-0.000056,0.000071,-0.000057),(-0.000029,0.000011,-0.000009),(0.000020,0.000001,0.000020),(-0.000009,0.000028,-0.000008),(-0.000036,0.000043,-0.000048),(-0.000012,0.000012,-0.000029),(0.000016,0.000004,0.000008),(0.000007,0.000008,0.000015),(0.000002,0.000021,0.000003),(0.000022,0.000007,0.000014),(0.000002,0.000023,0.000002),(0.000014,0.000010,0.000022),(0.000034,0.000015,0.000036),(-0.000039,0.000016,-0.000054),(-0.000021,0.000024,-0.000017),(-0.000001,-0.000014,0.000013),(-0.000003,0.000022,-0.000013),(-0.000189,0.000199,-0.000226),(-0.000022,0.000007,-0.000018),(0.000009,-0.000009,-0.000019),(-0.000014,0.000018,0.000003),(0.000035,-0.000013,0.000032),(0.000002,0.000031,0.000005),(0.000045,-0.000013,0.000021),(0.000021,-0.000005,0.000046),(0.000022,0.000016,0.000021),(0.000049,-0.000008,0.000029),(0.000017,0.000021,0.000023),(0.000032,-0.000003,0.000050),(0.000060,0.000018,0.000061),(-0.000067,0.000023,-0.000096),(-0.000019,0.000026,-0.000011),(-0.000014,-0.000012,0.000008),(0.000008,0.000023,-0.000004),(-0.000262,0.000177,-0.000321),(-0.000021,0.000001,-0.000012),(0.000009,-0.000006,-0.000047),(-0.000007,0.000016,0.000017),(0.000050,-0.000013,0.000041),(0.000016,0.000038,0.000021),(0.000046,0.000016,0.000040),(0.000077,-0.000010,0.000040),(0.000036,0.000023,0.000049),(0.000048,-0.000006,0.000079),(0.000085,0.000042,0.000083),(-0.000070,0.000022,-0.000113),(-0.000028,0.000039,-0.000017),(0.000072,0.000003,0.000055),(0.000023,0.000061,0.000029),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000011,0.000010,-0.000019),(0.000004,0.000001,-0.000003),(0.000006,0.000014,0.000009)};
    //double energy[221] = {1.542830e-42,0.000000e+00,1.017876e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-2.317951e+13,1.926055e-04,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,7.229655e-17,4.577482e-41,7.230719e-17,4.577482e-41,0.000000e+00,0.000000e+00,7.230781e-17,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,6.532545e-27,4.577482e-41,-3.194302e-38,5.898247e-02,4.237519e-37,9.809089e-45,3.363116e-44,0.000000e+00,2.025024e-08,0.000000e+00,2.848895e-08,1.511689e-09,2.150964e-08,0.000000e+00,1.541544e-08,1.854911e-07,2.257209e-08,0.000000e+00,1.605298e-08,7.123480e-09,2.104863e-07,0.000000e+00,9.799036e-05,1.466930e-04,2.309945e-04,0.000000e+00,1.562906e-04,1.148952e-04,1.203459e-04,0.000000e+00,3.012822e-04,4.234389e-05,2.005827e-04,0.000000e+00,8.251942e-05,1.142085e-04,8.502679e-05,0.000000e+00,3.224969e-04,1.431179e-04,3.734327e-04,0.000000e+00,3.013988e-03,1.226029e-03,2.129179e-02,0.000000e+00,1.464419e-02,5.501955e-03,1.881593e-02,0.000000e+00,1.660532e-02,7.767329e-03,9.980457e-03,0.000000e+00,1.278249e-02,1.585113e-03,1.794737e-02,0.000000e+00,1.581253e-02,5.122344e-03,4.728785e-03,-7.521544e-06,-3.115620e+05,7.524181e+01,2.789771e-02,-2.056223e-05,1.973437e+27,4.870370e+01,3.909907e-02,-2.700995e-05,8.916755e-01,6.818591e+01,3.266954e-02,-3.893143e-06,2.683526e-27,2.092911e-23,8.694591e-26,0.000000e+00,9.707691e-21,4.164478e-27,5.105821e-26,0.000000e+00,5.618195e-22,8.011395e-23,7.939312e-27,0.000000e+00,1.583467e-42,1.401298e-45,1.014504e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-3.194302e-38,5.898247e-02,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,6.283977e-17,4.577482e-41,6.284513e-17,4.577482e-41,0.000000e+00,0.000000e+00,6.284652e-17,4.577482e-41,0.000000e+00,0.000000e+00,1.399897e-42,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,4.237290e-37,9.809089e-45,-2.317951e+13,1.926055e-04,4.237290e-37,9.809089e-45,3.363116e-44,0.000000e+00,2.088217e-27,0.000000e+00,1.568769e-26,6.419391e-27,3.931566e-23,0.000000e+00,6.554724e-27,3.067580e-27,2.328027e-26,0.000000e+00,1.053539e-26,5.014781e-27,7.749388e-24,0.000000e+00,8.620366e-28,2.289166e-27,5.293036e-27,0.000000e+00,6.232589e-27,5.673471e-27,2.332169e-26,0.000000e+00,1.177772e-08,2.611032e-09,1.260247e-08,0.000000e+00,3.821657e-08,2.177334e-09,7.358555e-09,0.000000e+00,4.254145e-09,1.708416e-09,7.111237e-09,0.000000e+00,5.839961e-09,8.409097e-09,4.951757e-09,0.000000e+00,2.549411e-09,1.483298e-09,1.624575e-09,0.000000e+00,1.740956e-09};
    //double factor[221] = {1.542830e-42,0.000000e+00,1.017876e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-2.317951e+13,1.926055e-04,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,7.229655e-17,4.577482e-41,7.230719e-17,4.577482e-41,0.000000e+00,0.000000e+00,7.230781e-17,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,6.530166e-27,4.577482e-41,-3.194302e-38,5.898247e-02,4.237519e-37,9.809089e-45,3.363116e-44,0.000000e+00,6.836695e-12,1.675647e-11,6.620036e-12,6.265301e-12,6.394112e-12,6.476615e-12,7.319163e-12,3.605303e-11,6.644645e-12,6.467787e-12,6.112196e-12,5.683108e-12,6.599283e-12,6.844061e-12,6.563489e-12,6.017392e-12,6.399866e-12,6.154383e-12,3.026520e-07,3.557238e-07,3.342354e-07,3.519032e-07,3.405898e-07,3.512081e-07,3.150973e-07,3.629471e-07,3.268906e-07,3.745598e-07,3.230706e-07,3.582586e-07,3.422037e-07,3.462203e-07,3.601238e-07,3.121515e-07,3.722795e-07,3.343488e-07,3.569448e-07,3.585053e-07,3.710899e-07,3.638215e-07,3.261631e-07,3.464344e-07,3.334570e-07,4.756184e-05,4.773591e-05,4.515327e-05,4.688610e-05,4.413019e-05,4.858421e-05,4.693521e-05,5.063206e-05,4.833565e-05,4.781871e-05,4.642509e-05,4.634951e-05,5.089617e-05,4.829466e-05,5.122057e-05,3.713917e-05,4.961211e-05,4.833119e-05,3.915227e-05,4.985524e-05,4.954117e-05,4.686260e-04,4.303385e-04,3.447189e-04,4.114783e-04,4.361123e-04,4.445273e-04,4.612404e-04,4.645406e-04,4.760396e-04,4.713000e-04,4.726021e-04,4.226256e-04,4.610711e-04,4.390908e-04,1.583467e-42,1.401298e-45,1.014504e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-3.194302e-38,5.898247e-02,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,6.283977e-17,4.577482e-41,6.284513e-17,4.577482e-41,0.000000e+00,0.000000e+00,6.284652e-17,4.577482e-41,0.000000e+00,0.000000e+00,1.399897e-42,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,4.237290e-37,9.809089e-45,-2.317951e+13,1.926055e-04,4.237290e-37,9.809089e-45,3.363116e-44,0.000000e+00,1.856939e-05,4.965303e-05,7.526137e-05,6.964390e-07,1.641322e-04,3.707860e-06,2.637519e-04,2.127130e-04,2.210860e-05,1.228141e-07,5.726594e-04,4.518460e-04,1.110597e-05,1.670070e-05,5.406669e-04,6.669017e-04,8.500725e-05,6.133204e-04,2.710157e-04,1.765020e-04,3.489698e-05,4.957735e-04,4.268136e-04,2.140554e-22,2.745518e-24,1.099713e-26,1.039016e-25,7.914708e-22,1.839824e-20,9.827770e-23,8.790141e-24,4.658280e-18,2.503744e-16,3.010181e-19,5.753074e-22,6.707894e-21,5.924780e-21,1.547127e-26,1.484105e-24,6.045916e-25,5.328845e-06,2.523798e-05,1.002050e-05};
    //double point_weights[221] = {0.000000e+00,0.000000e+00,6.356219e-06,3.324887e-04,3.143648e-02,3.212402e-01,1.299464e-05,7.277725e-04,0.000000e+00,2.066700e+00,2.379370e-01,5.970362e-02,6.884030e-05,1.351831e-03,7.788771e-02,2.020641e-03,1.322531e-06,3.924060e-06,1.305768e-06,1.925648e-04,1.586370e-02,3.594067e-04,1.449458e-01,7.987326e-06,4.113678e-04,0.000000e+00,1.094970e-01,3.780463e-02,0.000000e+00,5.679121e-06,0.000000e+00,2.230565e-04,1.453141e-02,4.649304e-04,0.000000e+00,8.580421e-02,3.249447e-02,0.000000e+00,1.818959e-05,1.134347e-03,1.042623e-01,4.639464e-02,6.318915e-03,1.360220e+02,1.326793e+02,1.313792e+02,1.313792e+02,1.313792e+02,1.227952e+02,1.227954e+02,1.227835e+02,1.335201e+02,1.335201e+02,1.335200e+02,9.516099e+01,9.764464e+01,9.107944e+01,9.713596e+01,1.196765e+02,1.200841e+02,1.316433e+02,1.316505e+02,1.316438e+02,1.316480e+02,1.316498e+02,1.316524e+02,1.772504e+01,1.728354e+01,1.711418e+01,1.711418e+01,1.711418e+01,1.599609e+01,1.599612e+01,1.599554e+01,1.739307e+01,1.739307e+01,1.739307e+01,1.258319e+01,1.272966e+01,1.273444e+01,1.230952e+01,1.270183e+01,1.563527e+01,1.565721e+01,1.714936e+01,1.706164e+01,1.714969e+01,1.714966e+01,1.714972e+01,1.714966e+01,1.709727e+01,1.714977e+01,3.601541e+00,3.511343e+00,3.476937e+00,3.476937e+00,3.476937e+00,3.212072e+00,3.249791e+00,3.249793e+00,3.174251e+00,3.249757e+00,3.533596e+00,3.504852e+00,3.533596e+00,3.533596e+00,2.576064e+00,2.586982e+00,2.587315e+00,2.553255e+00,2.585052e+00,3.180675e+00,3.182183e+00,3.484143e+00,3.477949e+00,3.484163e+00,3.484166e+00,3.484167e+00,3.484161e+00,3.480554e+00,3.484168e+00,9.663483e-01,8.954918e-01,9.421041e-01,9.202220e-01,9.328728e-01,9.328728e-01,9.153517e-01,9.328728e-01,8.686274e-01,8.719293e-01,8.719295e-01,8.649900e-01,8.719268e-01,9.480746e-01,9.456108e-01,9.480746e-01,9.480746e-01,8.537841e-01,8.539019e-01,9.348111e-01,9.343160e-01,9.348124e-01,9.345296e-01,3.132776e-01,3.003089e-01,3.054141e-01,3.011668e-01,3.024214e-01,2.675158e-01,3.024214e-01,3.006469e-01,3.024214e-01,2.823578e-01,2.826646e-01,2.826646e-01,2.819968e-01,2.826644e-01,2.886273e-01,3.073496e-01,3.071240e-01,3.073496e-01,2.925198e-01,3.073496e-01,2.768208e-01,2.768309e-01,3.030502e-01,3.030071e-01,3.030503e-01,3.030261e-01,1.163402e-01,1.128603e-01,1.134196e-01,1.121797e-01,1.123082e-01,1.077705e-01,1.123082e-01,1.121239e-01,1.123082e-01,1.141165e-01,1.141384e-01,1.028049e-01,1.028059e-01,1.125418e-01,1.125377e-01,1.125418e-01,1.125395e-01,4.780666e-02,4.654431e-02,4.660649e-02,4.613614e-02,4.614981e-02,4.558606e-02,4.614981e-02,4.613001e-02,4.614981e-02,4.689961e-02,4.690185e-02,4.624578e-02,4.624538e-02,4.624578e-02,4.624556e-02,2.122287e-02,2.068298e-02,2.069007e-02,2.082095e-02,2.082120e-02,2.571491e-07,3.053828e-05,3.673155e-03,1.025607e-02,0.000000e+00,0.000000e+00,1.847405e-06,1.768821e-07,0.000000e+00,0.000000e+00,4.100356e-04,8.746948e-10,1.113151e-13,4.551340e-11};
    //double partial_densities[221] = {1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38,6.815741e-37,2.776831e-36,1.143339e-34,3.467837e-35,2.173183e-36,2.919116e-35,3.249745e-13,1.280894e-13,2.872959e-13,5.841356e-14,1.052731e-14,4.778827e-14,2.419135e-15,1.127769e-13,4.739891e-14,2.618893e-13,3.192557e-15,6.648584e-15,4.077459e-07,2.149901e-07,3.746791e-07,1.251948e-07,3.841547e-08,1.084211e-07,3.515827e-07,1.679403e-08,2.794462e-08,3.479711e-05,2.007635e-05,1.120590e-05,2.301993e-06,3.572237e-06,1.566220e-05,5.111461e-31,5.111677e-31,5.111461e-31,5.111597e-31,5.111461e-31,5.111840e-31,5.111245e-31,5.111542e-31,5.111677e-31,5.111786e-31,5.111677e-31,5.111892e-31,5.111867e-31,5.111594e-31,5.111542e-31,5.111461e-31,5.111461e-31,5.111489e-31,5.111542e-31,5.111299e-31,5.111867e-31,5.111786e-31,5.111299e-31,1.202872e-12,1.203062e-12,1.203132e-12,1.203147e-12,1.203080e-12,1.203036e-12,1.203051e-12,1.202950e-12,1.203056e-12,1.203025e-12,1.203067e-12,1.201019e-12,1.202777e-12,1.202918e-12,1.198146e-12,1.202207e-12,1.202323e-12,1.202721e-12,1.202982e-12,1.201824e-12,1.203016e-12,1.203111e-12,1.203109e-12,1.203064e-12,1.202214e-12,1.203094e-12,1.056859e-07,1.069813e-07,1.068918e-07,1.069731e-07,1.067879e-07,9.925203e-08,1.065169e-07,1.067720e-07,9.567351e-08,1.061269e-07,1.068738e-07,1.002584e-07,1.067610e-07,1.069669e-07,1.020017e-07,1.054180e-07,1.061756e-07,9.844285e-08,1.040931e-07,1.043744e-07,1.052831e-07,1.062094e-07,1.033102e-07,1.064327e-07,1.068430e-07,1.067436e-07,1.064088e-07,1.040096e-07,1.067188e-07,5.449067e-06,2.706551e-06,5.836964e-06,3.695634e-06,5.801161e-06,5.833626e-06,3.451926e-06,5.762271e-06,4.397482e-06,5.673675e-06,5.758306e-06,3.997644e-06,5.560026e-06,5.793905e-06,4.525559e-06,5.752838e-06,5.831018e-06,5.168859e-06,5.356980e-06,5.582546e-06,4.978430e-06,5.640204e-06,5.102124e-06,2.601504e-05,9.496978e-06,3.058765e-05,1.358994e-05,3.008526e-05,2.710820e-05,3.054102e-05,1.249342e-05,2.956473e-05,1.764504e-05,2.846226e-05,2.951743e-05,1.532756e-05,2.717309e-05,1.355043e-05,2.998640e-05,1.852374e-05,2.944374e-05,1.020576e-05,3.050481e-05,2.341930e-05,2.510869e-05,2.741899e-05,2.183935e-05,2.806830e-05,2.283266e-05,5.046140e-05,1.499352e-05,6.507664e-05,2.169488e-05,6.326965e-05,4.041267e-05,6.489926e-05,1.996210e-05,6.149049e-05,3.179689e-05,6.107018e-05,4.349307e-05,4.785749e-05,5.461262e-05,3.951244e-05,5.657595e-05,4.188267e-05,6.643681e-05,1.701268e-05,9.193084e-05,2.527302e-05,8.849833e-05,3.780743e-05,9.155914e-05,2.338526e-05,8.530516e-05,3.873166e-05,8.451808e-05,7.331888e-05,4.973260e-05,7.654892e-05,5.304757e-05,7.487628e-05,1.748799e-05,1.078457e-04,4.236045e-05,9.790303e-05,4.905088e-17,3.745068e-17,4.379298e-19,1.966976e-19,5.755041e-15,2.728153e-14,1.389058e-16,3.278741e-16,4.960657e-15,6.570254e-15,9.327300e-19,1.487219e-05,5.521405e-06,1.366262e-05};

    double partial_densities_cpu[10] = {1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38};
    double point_weights_cpu[10] = {0.000000e+00,0.000000e+00,6.356219e-06,3.324887e-04,3.143648e-02,3.212402e-01,1.299464e-05,7.277725e-04,0.000000e+00,2.066700e+00};
    double input[number_of_points];
    for (int i=0; i<number_of_points; i++) {
	input[i]=0.001*i;
    }
    cudaMemset(energy_gpu_in, 0, size);
    cudaMemset(factor_gpu_in, 0, size);
    //cudaMemcpy(energy_gpu_in, input, size, cudaMemcpyHostToDevice);
    //cudaMemcpy(factor_gpu_in, input, size, cudaMemcpyHostToDevice);
    cudaMemcpy(point_weights_gpu_in, point_weights_cpu, size, cudaMemcpyHostToDevice);
    cudaMemcpy(partial_density_gpu_in, partial_densities_cpu, size, cudaMemcpyHostToDevice);
    //cudaMemcpy(dxyz_gpu_in.data, input, size, cudaMemcpyHostToDevice);
    //cudaMemcpy(dd1_gpu_in.data, input, size, cudaMemcpyHostToDevice);
    //cudaMemcpy(dd2_gpu_in.data, input, size, cudaMemcpyHostToDevice);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    /////////////////////////////////
    // LIBXC VERSION
    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
    gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid,threadsPerBlock>>> (point_weights_gpu_in,
	number_of_points, block_height,
	partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	partial_density_gpu_accum, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);

    // Calculate exc_corr and y2a
    libxc_exchange_correlation_gpu<double, true, true, false> (&libxcProxy,
	energy_gpu_in,
	factor_gpu_in,
	number_of_points,
	partial_density_gpu_accum,
	dxyz_gpu_accum.data,
        dd1_gpu_accum.data,
	dd2_gpu_accum.data);
    
    // Join the results.
    gpu_accumulate_energy_and_forces_from_libxc<double, true, true, false><<<blocksPerGrid, threadsPerBlock>>> (
	energy_gpu_in,
	factor_gpu_in,
	point_weights_gpu_in,
	number_of_points,
	partial_density_gpu_accum);

    ///////////////////////////
    // Print libxc results
    // Allocate the host input vectors
    double *energy_cpu = (double *)malloc(size);
    double *factor_cpu = (double *)malloc(size);

    // Copy the vectors from gpu to cpu
    // Be aware that energy_gpu can be NULL.
    err = cudaMemcpy(energy_cpu, energy_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector energy_gpu_in from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(factor_cpu, factor_gpu_in, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector factor_gpu_in from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (NULL, NULL, NULL, energy_cpu,
	factor_cpu, NULL, NULL, number_of_points);

    ////////////////////////////////////////
    // LIO VERSION
    // Now the arrays for energy, factors
    double *energy_gpu_in2 = NULL;
    double *factor_gpu_in2 = NULL;
    err = cudaMalloc((void**)&energy_gpu_in2, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu_in2!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in2, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu_in2!\n");
    }

    gpu_accumulate_point<double, true, true, false><<<blocksPerGrid,threadsPerBlock>>> (
	energy_gpu_in2, 
	factor_gpu_in2,
	point_weights_gpu_in,
	number_of_points,
	block_height,
	partial_density_gpu_in,
	dxyz_gpu_in.data,
	dd1_gpu_in.data,
	dd2_gpu_in.data);

    ///////////////////////////////////////
    // Print LIO results.
    // Copy back the results before print.
    // Allocate the host input vectors
    double *energy_cpu2 = (double *)malloc(size);
    double *factor_cpu2 = (double *)malloc(size);

    // Copy the vectors from gpu to cpu
    // Be aware that energy_gpu can be NULL.
    err = cudaMemcpy(energy_cpu2, energy_gpu_in2, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector energy_gpu_in2 from device to host!\n");
        exit(EXIT_FAILURE);
    }

    err = cudaMemcpy(factor_cpu2, factor_gpu_in2, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
    {
        printf("Failed to copy vector factor_gpu_in2 from device to host!\n");
        exit(EXIT_FAILURE);
    }

    print_accumulate_point_data (NULL, NULL, NULL, energy_cpu2,
	factor_cpu2, NULL, NULL, number_of_points);

    ////////////////////////////
    // Free Memory CPU
    free(energy_cpu);
    free(factor_cpu);
    free(energy_cpu2);
    free(factor_cpu2);

    ///////////////////////////
    // Free memory GPU
    cudaFree (point_weights_gpu_in);
    cudaFree (partial_density_gpu_in);
    cudaFree (partial_density_gpu_accum);
    cudaFree (energy_gpu_in);
    cudaFree (factor_gpu_in);
    cudaFree (energy_gpu_in2);
    cudaFree (factor_gpu_in2);
#endif
}


/////////////////////////////////////////////////
//
void accumulate_data_for_libxc_test0008(int iterations) {
    printf("accumulate_data_for_libxc_test0008()\n");
#if FULL_DOUBLE
    cudaError_t err = cudaSuccess;
    uint n = 5;
    uint m = 5;
    uint number_of_points = n+m;

    // Input
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_in = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_in = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_in = createMatrix(number_of_points);

    // Accumulate
    G2G::CudaMatrix< G2G::vec_type<double,4> > dxyz_gpu_accum = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd1_gpu_accum = createMatrix(number_of_points);
    G2G::CudaMatrix< G2G::vec_type<double,4> > dd2_gpu_accum = createMatrix(number_of_points);

    dxyz_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_in.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_in.zero();
    dd1_gpu_in.zero();
    dd2_gpu_in.zero();

    dxyz_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd1_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);
    dd2_gpu_accum.resize(COALESCED_DIMENSION(number_of_points),m);

    dxyz_gpu_accum.zero();
    dd1_gpu_accum.zero();
    dd2_gpu_accum.zero();

    // Now the arrays for energy, factors, point_weight and partial_density
    double *point_weights_gpu_in = NULL;
    double *partial_density_gpu_in = NULL;
    // Accum
    double *partial_density_gpu_accum = NULL;

    // Create the arrays in CUDA memory.
    uint size = number_of_points * sizeof(double);
    err = cudaMalloc((void**)&point_weights_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector point_weights_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_in!\n");
    }

    err = cudaMalloc((void**)&partial_density_gpu_accum, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector partial_density_gpu_accum!\n");
    }

    // Now the arrays for energy, factors
    double *energy_gpu_in = NULL;
    double *factor_gpu_in = NULL;
    err = cudaMalloc((void**)&energy_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector energy_gpu!\n");
    }

    err = cudaMalloc((void**)&factor_gpu_in, size);
    if (err != cudaSuccess)
    {
	printf("Failed to allocate vector factor_gpu!\n");
    }

    // Launch the CUDA Kernel
    int numElements = n+m;
    int threadsPerBlock = 32;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    uint block_height = 1;

    ///////////////////////
    // Set data
    //=========
    //= Data  =
    //=========
    //number_of_points:221
    //block_height:1
    //double dxyz[221] = {(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000001,-0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000001,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000001,0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000035,-0.000017,0.000026),(0.000009,0.000001,0.000028),(0.000013,0.000007,0.000010),(0.000003,0.000003,0.000001),(0.000002,0.000004,0.000005),(-0.000000,0.000017,-0.000003),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000008,0.000000,0.000008),(0.000002,0.000004,0.000002),(0.000007,-0.000007,0.000007),(0.000002,0.000005,0.000004),(0.000005,-0.000005,0.000009),(0.000005,-0.000009,0.000005),(0.000004,0.000004,0.000002),(0.000009,-0.000005,0.000005),(0.000002,0.000004,0.000007),(0.000003,-0.000003,0.000011),(0.000003,-0.000011,0.000003),(0.000006,0.000004,0.000001),(0.000010,-0.000003,0.000003),(0.000008,-0.000008,0.000004),(0.000005,0.000004,0.000005),(0.000008,-0.000004,0.000008),(0.000004,-0.000008,0.000008),(0.000010,0.000001,0.000003),(0.000003,0.000001,0.000010),(0.000009,-0.000001,0.000006),(0.000008,0.000002,0.000005),(0.000006,-0.000002,0.000010),(0.000005,0.000002,0.000008),(0.000025,0.000007,0.000024),(0.000003,0.000011,0.000002),(0.000026,-0.000025,0.000025),(0.000001,0.000019,0.000006),(0.000019,-0.000018,0.000034),(0.000055,-0.000034,0.000067),(0.000019,-0.000035,0.000019),(0.000007,0.000017,-0.000000),(0.000034,-0.000017,0.000018),(0.000001,0.000018,0.000015),(0.000010,-0.000008,0.000037),(0.000011,-0.000039,0.000010),(0.000013,0.000017,-0.000002),(0.000036,-0.000007,0.000008),(0.000025,-0.000013,0.000025),(0.000030,-0.000028,0.000012),(0.000012,0.000019,0.000010),(0.000029,-0.000010,0.000028),(0.000011,-0.000005,0.000017),(0.000013,-0.000029,0.000030),(0.000029,0.000008,0.000006),(0.000009,0.000007,0.000031),(0.000033,-0.000001,0.000018),(0.000022,0.000014,0.000010),(0.000020,-0.000002,0.000033),(0.000013,0.000014,0.000023),(0.000031,0.000025,0.000028),(-0.000001,0.000014,-0.000001),(0.000040,-0.000035,0.000037),(-0.000007,0.000036,-0.000002),(0.000026,-0.000020,0.000053),(0.000077,-0.000088,0.000098),(0.000028,-0.000053,0.000025),(0.000001,0.000031,-0.000009),(0.000053,-0.000018,0.000021),(0.000007,0.000042,0.000003),(0.000043,-0.000007,0.000040),(0.000036,0.000028,-0.000003),(0.000004,0.000027,0.000039),(0.000047,0.000011,0.000020),(0.000024,0.000037,0.000004),(0.000025,0.000010,0.000046),(0.000010,0.000037,0.000023),(0.000027,0.000054,0.000019),(-0.000008,0.000019,-0.000007),(0.000041,-0.000028,0.000034),(-0.000018,0.000055,-0.000013),(0.000021,-0.000008,0.000054),(0.000066,-0.000120,0.000090),(0.000024,-0.000052,0.000017),(-0.000008,0.000046,-0.000019),(0.000057,-0.000004,0.000011),(-0.000003,0.000069,-0.000010),(0.000044,0.000011,0.000037),(0.000048,0.000036,0.000009),(0.000018,0.000066,-0.000011),(0.000019,0.000034,0.000044),(-0.000001,0.000067,0.000014),(0.000023,0.000084,0.000011),(-0.000016,0.000035,-0.000016),(0.000037,-0.000014,0.000026),(-0.000009,0.000097,-0.000018),(0.000042,0.000035,0.000030),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000009,-0.000018,0.000016),(0.000005,0.000007,0.000001),(0.000011,0.000005,0.000018)};
    //double dd1[221] = {(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000001,0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000002,0.000000),(0.000001,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000000,0.000001,0.000001),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000014,-0.000019,-0.000005),(-0.000011,-0.000016,0.000027),(0.000007,-0.000005,0.000001),(0.000003,0.000002,-0.000002),(-0.000002,0.000002,0.000003),(-0.000004,0.000095,0.000018),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,-0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000001),(-0.000000,-0.000000,0.000001),(-0.000000,0.000001,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,0.000000),(0.000000,-0.000000,0.000001),(0.000001,-0.000000,0.000000),(0.000001,-0.000000,0.000000),(0.000001,0.000000,-0.000000),(-0.000000,0.000001,0.000000),(-0.000000,0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000001,-0.000000),(0.000007,-0.000004,0.000007),(-0.000000,0.000006,-0.000000),(0.000005,0.000004,0.000004),(-0.000002,0.000003,0.000002),(0.000001,0.000001,0.000011),(0.000001,0.000011,0.000001),(0.000002,0.000003,-0.000002),(0.000011,0.000001,0.000001),(-0.000002,-0.000000,0.000008),(-0.000002,-0.000002,0.000016),(-0.000002,0.000016,-0.000002),(0.000007,0.000000,-0.000003),(0.000016,-0.000002,-0.000002),(0.000007,0.000007,-0.000001),(0.000003,0.000000,0.000002),(0.000007,-0.000002,0.000007),(-0.000001,0.000007,0.000007),(0.000014,-0.000004,-0.000002),(-0.000001,-0.000004,0.000015),(0.000013,-0.000003,0.000002),(0.000009,-0.000002,0.000001),(0.000003,-0.000003,0.000013),(0.000001,-0.000003,0.000009),(0.000006,-0.000021,0.000003),(-0.000001,0.000033,0.000004),(0.000003,-0.000001,0.000001),(-0.000012,0.000018,-0.000012),(-0.000009,-0.000012,0.000021),(0.000108,0.000012,0.000166),(-0.000008,0.000020,-0.000010),(-0.000008,0.000020,-0.000010),(0.000022,-0.000013,-0.000011),(-0.000016,0.000001,-0.000004),(-0.000017,-0.000021,0.000032),(-0.000017,0.000034,-0.000019),(-0.000002,0.000006,-0.000014),(0.000031,-0.000021,-0.000019),(0.000058,0.000034,0.000070),(0.000011,0.000006,-0.000017),(-0.000008,0.000002,-0.000012),(0.000010,-0.000019,0.000007),(0.000028,0.000035,0.000056),(-0.000016,0.000008,0.000010),(0.000021,-0.000019,-0.000019),(-0.000016,-0.000021,0.000022),(0.000023,-0.000023,-0.000008),(0.000007,-0.000011,-0.000014),(-0.000005,-0.000023,0.000021),(-0.000010,-0.000013,0.000005),(-0.000018,-0.000049,-0.000029),(0.000003,0.000100,0.000020),(-0.000023,-0.000037,-0.000030),(-0.000023,0.000058,-0.000029),(-0.000041,-0.000054,0.000001),(0.000149,0.000116,0.000241),(-0.000040,-0.000004,-0.000046),(-0.000022,0.000066,-0.000011),(0.000008,-0.000054,-0.000048),(-0.000032,0.000016,-0.000039),(-0.000012,-0.000062,-0.000021),(0.000003,-0.000041,-0.000050),(-0.000046,-0.000047,-0.000002),(0.000007,-0.000061,-0.000044),(-0.000016,-0.000018,-0.000045),(-0.000035,-0.000062,-0.000001),(-0.000038,-0.000023,-0.000025),(-0.000040,-0.000078,-0.000057),(0.000006,0.000207,0.000035),(-0.000058,-0.000088,-0.000072),(-0.000028,0.000128,-0.000030),(-0.000083,-0.000109,-0.000022),(0.000146,0.000282,0.000245),(-0.000084,-0.000038,-0.000096),(-0.000027,0.000142,-0.000004),(-0.000007,-0.000109,-0.000095),(-0.000047,0.000050,-0.000053),(-0.000038,-0.000118,-0.000055),(-0.000003,-0.000105,-0.000083),(-0.000026,-0.000015,-0.000070),(-0.000070,-0.000109,-0.000020),(-0.000064,-0.000024,-0.000042),(-0.000057,-0.000111,-0.000077),(-0.000002,0.000337,0.000033),(-0.000100,-0.000144,-0.000121),(-0.000057,0.000094,-0.000062),(-0.000065,-0.000183,-0.000088),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000004,0.000013,0.000007),(0.000001,0.000011,-0.000001),(-0.000000,-0.000009,0.000014)};
    //double dd2[221] = {(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000001,0.000001,-0.000001),(-0.000000,0.000001,-0.000000),(-0.000001,0.000000,-0.000001),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000017,0.000027,-0.000011),(0.000003,0.000011,0.000005),(0.000010,0.000011,0.000009),(0.000005,0.000000,0.000001),(0.000003,0.000002,0.000007),(-0.000028,0.000011,-0.000050),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000001,0.000010,0.000001),(0.000002,0.000001,0.000002),(-0.000008,0.000008,-0.000008),(0.000003,0.000002,0.000006),(-0.000005,0.000008,-0.000008),(-0.000008,0.000005,-0.000008),(0.000006,0.000001,0.000003),(-0.000008,0.000008,-0.000004),(0.000002,0.000002,0.000007),(-0.000002,0.000006,-0.000006),(-0.000006,0.000002,-0.000006),(0.000007,0.000001,0.000002),(-0.000005,0.000005,-0.000001),(-0.000011,0.000005,-0.000005),(0.000005,0.000005,0.000005),(-0.000005,0.000011,-0.000005),(-0.000005,0.000005,-0.000011),(0.000002,0.000005,0.000001),(0.000001,0.000006,0.000002),(-0.000002,0.000010,-0.000001),(0.000005,0.000007,0.000003),(-0.000001,0.000010,-0.000002),(0.000003,0.000008,0.000004),(0.000011,0.000022,0.000012),(-0.000008,0.000006,-0.000012),(-0.000021,0.000022,-0.000020),(0.000007,-0.000005,0.000015),(-0.000010,0.000022,-0.000020),(-0.000080,0.000147,-0.000094),(-0.000022,0.000011,-0.000021),(0.000013,-0.000005,0.000001),(-0.000019,0.000020,-0.000008),(0.000007,-0.000006,0.000026),(-0.000000,0.000012,-0.000008),(-0.000013,0.000002,-0.000012),(0.000022,-0.000008,0.000003),(-0.000006,0.000008,0.000002),(-0.000056,0.000071,-0.000057),(-0.000029,0.000011,-0.000009),(0.000020,0.000001,0.000020),(-0.000009,0.000028,-0.000008),(-0.000036,0.000043,-0.000048),(-0.000012,0.000012,-0.000029),(0.000016,0.000004,0.000008),(0.000007,0.000008,0.000015),(0.000002,0.000021,0.000003),(0.000022,0.000007,0.000014),(0.000002,0.000023,0.000002),(0.000014,0.000010,0.000022),(0.000034,0.000015,0.000036),(-0.000039,0.000016,-0.000054),(-0.000021,0.000024,-0.000017),(-0.000001,-0.000014,0.000013),(-0.000003,0.000022,-0.000013),(-0.000189,0.000199,-0.000226),(-0.000022,0.000007,-0.000018),(0.000009,-0.000009,-0.000019),(-0.000014,0.000018,0.000003),(0.000035,-0.000013,0.000032),(0.000002,0.000031,0.000005),(0.000045,-0.000013,0.000021),(0.000021,-0.000005,0.000046),(0.000022,0.000016,0.000021),(0.000049,-0.000008,0.000029),(0.000017,0.000021,0.000023),(0.000032,-0.000003,0.000050),(0.000060,0.000018,0.000061),(-0.000067,0.000023,-0.000096),(-0.000019,0.000026,-0.000011),(-0.000014,-0.000012,0.000008),(0.000008,0.000023,-0.000004),(-0.000262,0.000177,-0.000321),(-0.000021,0.000001,-0.000012),(0.000009,-0.000006,-0.000047),(-0.000007,0.000016,0.000017),(0.000050,-0.000013,0.000041),(0.000016,0.000038,0.000021),(0.000046,0.000016,0.000040),(0.000077,-0.000010,0.000040),(0.000036,0.000023,0.000049),(0.000048,-0.000006,0.000079),(0.000085,0.000042,0.000083),(-0.000070,0.000022,-0.000113),(-0.000028,0.000039,-0.000017),(0.000072,0.000003,0.000055),(0.000023,0.000061,0.000029),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000011,0.000010,-0.000019),(0.000004,0.000001,-0.000003),(0.000006,0.000014,0.000009)};
    //double energy[221] = {1.542830e-42,0.000000e+00,1.017876e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-2.317951e+13,1.926055e-04,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,7.229655e-17,4.577482e-41,7.230719e-17,4.577482e-41,0.000000e+00,0.000000e+00,7.230781e-17,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,6.532545e-27,4.577482e-41,-3.194302e-38,5.898247e-02,4.237519e-37,9.809089e-45,3.363116e-44,0.000000e+00,2.025024e-08,0.000000e+00,2.848895e-08,1.511689e-09,2.150964e-08,0.000000e+00,1.541544e-08,1.854911e-07,2.257209e-08,0.000000e+00,1.605298e-08,7.123480e-09,2.104863e-07,0.000000e+00,9.799036e-05,1.466930e-04,2.309945e-04,0.000000e+00,1.562906e-04,1.148952e-04,1.203459e-04,0.000000e+00,3.012822e-04,4.234389e-05,2.005827e-04,0.000000e+00,8.251942e-05,1.142085e-04,8.502679e-05,0.000000e+00,3.224969e-04,1.431179e-04,3.734327e-04,0.000000e+00,3.013988e-03,1.226029e-03,2.129179e-02,0.000000e+00,1.464419e-02,5.501955e-03,1.881593e-02,0.000000e+00,1.660532e-02,7.767329e-03,9.980457e-03,0.000000e+00,1.278249e-02,1.585113e-03,1.794737e-02,0.000000e+00,1.581253e-02,5.122344e-03,4.728785e-03,-7.521544e-06,-3.115620e+05,7.524181e+01,2.789771e-02,-2.056223e-05,1.973437e+27,4.870370e+01,3.909907e-02,-2.700995e-05,8.916755e-01,6.818591e+01,3.266954e-02,-3.893143e-06,2.683526e-27,2.092911e-23,8.694591e-26,0.000000e+00,9.707691e-21,4.164478e-27,5.105821e-26,0.000000e+00,5.618195e-22,8.011395e-23,7.939312e-27,0.000000e+00,1.583467e-42,1.401298e-45,1.014504e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-3.194302e-38,5.898247e-02,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,6.283977e-17,4.577482e-41,6.284513e-17,4.577482e-41,0.000000e+00,0.000000e+00,6.284652e-17,4.577482e-41,0.000000e+00,0.000000e+00,1.399897e-42,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,4.237290e-37,9.809089e-45,-2.317951e+13,1.926055e-04,4.237290e-37,9.809089e-45,3.363116e-44,0.000000e+00,2.088217e-27,0.000000e+00,1.568769e-26,6.419391e-27,3.931566e-23,0.000000e+00,6.554724e-27,3.067580e-27,2.328027e-26,0.000000e+00,1.053539e-26,5.014781e-27,7.749388e-24,0.000000e+00,8.620366e-28,2.289166e-27,5.293036e-27,0.000000e+00,6.232589e-27,5.673471e-27,2.332169e-26,0.000000e+00,1.177772e-08,2.611032e-09,1.260247e-08,0.000000e+00,3.821657e-08,2.177334e-09,7.358555e-09,0.000000e+00,4.254145e-09,1.708416e-09,7.111237e-09,0.000000e+00,5.839961e-09,8.409097e-09,4.951757e-09,0.000000e+00,2.549411e-09,1.483298e-09,1.624575e-09,0.000000e+00,1.740956e-09};
    //double factor[221] = {1.542830e-42,0.000000e+00,1.017876e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-2.317951e+13,1.926055e-04,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,7.229655e-17,4.577482e-41,7.230719e-17,4.577482e-41,0.000000e+00,0.000000e+00,7.230781e-17,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,6.530166e-27,4.577482e-41,-3.194302e-38,5.898247e-02,4.237519e-37,9.809089e-45,3.363116e-44,0.000000e+00,6.836695e-12,1.675647e-11,6.620036e-12,6.265301e-12,6.394112e-12,6.476615e-12,7.319163e-12,3.605303e-11,6.644645e-12,6.467787e-12,6.112196e-12,5.683108e-12,6.599283e-12,6.844061e-12,6.563489e-12,6.017392e-12,6.399866e-12,6.154383e-12,3.026520e-07,3.557238e-07,3.342354e-07,3.519032e-07,3.405898e-07,3.512081e-07,3.150973e-07,3.629471e-07,3.268906e-07,3.745598e-07,3.230706e-07,3.582586e-07,3.422037e-07,3.462203e-07,3.601238e-07,3.121515e-07,3.722795e-07,3.343488e-07,3.569448e-07,3.585053e-07,3.710899e-07,3.638215e-07,3.261631e-07,3.464344e-07,3.334570e-07,4.756184e-05,4.773591e-05,4.515327e-05,4.688610e-05,4.413019e-05,4.858421e-05,4.693521e-05,5.063206e-05,4.833565e-05,4.781871e-05,4.642509e-05,4.634951e-05,5.089617e-05,4.829466e-05,5.122057e-05,3.713917e-05,4.961211e-05,4.833119e-05,3.915227e-05,4.985524e-05,4.954117e-05,4.686260e-04,4.303385e-04,3.447189e-04,4.114783e-04,4.361123e-04,4.445273e-04,4.612404e-04,4.645406e-04,4.760396e-04,4.713000e-04,4.726021e-04,4.226256e-04,4.610711e-04,4.390908e-04,1.583467e-42,1.401298e-45,1.014504e-16,4.577482e-41,2.802597e-45,0.000000e+00,2.620864e-16,4.577482e-41,2.620872e-16,4.577482e-41,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.003857e-43,0.000000e+00,-3.194302e-38,5.898247e-02,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,6.283977e-17,4.577482e-41,6.284513e-17,4.577482e-41,0.000000e+00,0.000000e+00,6.284652e-17,4.577482e-41,0.000000e+00,0.000000e+00,1.399897e-42,1.401298e-45,1.401298e-45,1.401298e-45,1.401298e-45,4.577482e-41,4.237290e-37,9.809089e-45,-2.317951e+13,1.926055e-04,4.237290e-37,9.809089e-45,3.363116e-44,0.000000e+00,1.856939e-05,4.965303e-05,7.526137e-05,6.964390e-07,1.641322e-04,3.707860e-06,2.637519e-04,2.127130e-04,2.210860e-05,1.228141e-07,5.726594e-04,4.518460e-04,1.110597e-05,1.670070e-05,5.406669e-04,6.669017e-04,8.500725e-05,6.133204e-04,2.710157e-04,1.765020e-04,3.489698e-05,4.957735e-04,4.268136e-04,2.140554e-22,2.745518e-24,1.099713e-26,1.039016e-25,7.914708e-22,1.839824e-20,9.827770e-23,8.790141e-24,4.658280e-18,2.503744e-16,3.010181e-19,5.753074e-22,6.707894e-21,5.924780e-21,1.547127e-26,1.484105e-24,6.045916e-25,5.328845e-06,2.523798e-05,1.002050e-05};
    //double point_weights[221] = {0.000000e+00,0.000000e+00,6.356219e-06,3.324887e-04,3.143648e-02,3.212402e-01,1.299464e-05,7.277725e-04,0.000000e+00,2.066700e+00,2.379370e-01,5.970362e-02,6.884030e-05,1.351831e-03,7.788771e-02,2.020641e-03,1.322531e-06,3.924060e-06,1.305768e-06,1.925648e-04,1.586370e-02,3.594067e-04,1.449458e-01,7.987326e-06,4.113678e-04,0.000000e+00,1.094970e-01,3.780463e-02,0.000000e+00,5.679121e-06,0.000000e+00,2.230565e-04,1.453141e-02,4.649304e-04,0.000000e+00,8.580421e-02,3.249447e-02,0.000000e+00,1.818959e-05,1.134347e-03,1.042623e-01,4.639464e-02,6.318915e-03,1.360220e+02,1.326793e+02,1.313792e+02,1.313792e+02,1.313792e+02,1.227952e+02,1.227954e+02,1.227835e+02,1.335201e+02,1.335201e+02,1.335200e+02,9.516099e+01,9.764464e+01,9.107944e+01,9.713596e+01,1.196765e+02,1.200841e+02,1.316433e+02,1.316505e+02,1.316438e+02,1.316480e+02,1.316498e+02,1.316524e+02,1.772504e+01,1.728354e+01,1.711418e+01,1.711418e+01,1.711418e+01,1.599609e+01,1.599612e+01,1.599554e+01,1.739307e+01,1.739307e+01,1.739307e+01,1.258319e+01,1.272966e+01,1.273444e+01,1.230952e+01,1.270183e+01,1.563527e+01,1.565721e+01,1.714936e+01,1.706164e+01,1.714969e+01,1.714966e+01,1.714972e+01,1.714966e+01,1.709727e+01,1.714977e+01,3.601541e+00,3.511343e+00,3.476937e+00,3.476937e+00,3.476937e+00,3.212072e+00,3.249791e+00,3.249793e+00,3.174251e+00,3.249757e+00,3.533596e+00,3.504852e+00,3.533596e+00,3.533596e+00,2.576064e+00,2.586982e+00,2.587315e+00,2.553255e+00,2.585052e+00,3.180675e+00,3.182183e+00,3.484143e+00,3.477949e+00,3.484163e+00,3.484166e+00,3.484167e+00,3.484161e+00,3.480554e+00,3.484168e+00,9.663483e-01,8.954918e-01,9.421041e-01,9.202220e-01,9.328728e-01,9.328728e-01,9.153517e-01,9.328728e-01,8.686274e-01,8.719293e-01,8.719295e-01,8.649900e-01,8.719268e-01,9.480746e-01,9.456108e-01,9.480746e-01,9.480746e-01,8.537841e-01,8.539019e-01,9.348111e-01,9.343160e-01,9.348124e-01,9.345296e-01,3.132776e-01,3.003089e-01,3.054141e-01,3.011668e-01,3.024214e-01,2.675158e-01,3.024214e-01,3.006469e-01,3.024214e-01,2.823578e-01,2.826646e-01,2.826646e-01,2.819968e-01,2.826644e-01,2.886273e-01,3.073496e-01,3.071240e-01,3.073496e-01,2.925198e-01,3.073496e-01,2.768208e-01,2.768309e-01,3.030502e-01,3.030071e-01,3.030503e-01,3.030261e-01,1.163402e-01,1.128603e-01,1.134196e-01,1.121797e-01,1.123082e-01,1.077705e-01,1.123082e-01,1.121239e-01,1.123082e-01,1.141165e-01,1.141384e-01,1.028049e-01,1.028059e-01,1.125418e-01,1.125377e-01,1.125418e-01,1.125395e-01,4.780666e-02,4.654431e-02,4.660649e-02,4.613614e-02,4.614981e-02,4.558606e-02,4.614981e-02,4.613001e-02,4.614981e-02,4.689961e-02,4.690185e-02,4.624578e-02,4.624538e-02,4.624578e-02,4.624556e-02,2.122287e-02,2.068298e-02,2.069007e-02,2.082095e-02,2.082120e-02,2.571491e-07,3.053828e-05,3.673155e-03,1.025607e-02,0.000000e+00,0.000000e+00,1.847405e-06,1.768821e-07,0.000000e+00,0.000000e+00,4.100356e-04,8.746948e-10,1.113151e-13,4.551340e-11};
    //double partial_densities[221] = {1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38,6.815741e-37,2.776831e-36,1.143339e-34,3.467837e-35,2.173183e-36,2.919116e-35,3.249745e-13,1.280894e-13,2.872959e-13,5.841356e-14,1.052731e-14,4.778827e-14,2.419135e-15,1.127769e-13,4.739891e-14,2.618893e-13,3.192557e-15,6.648584e-15,4.077459e-07,2.149901e-07,3.746791e-07,1.251948e-07,3.841547e-08,1.084211e-07,3.515827e-07,1.679403e-08,2.794462e-08,3.479711e-05,2.007635e-05,1.120590e-05,2.301993e-06,3.572237e-06,1.566220e-05,5.111461e-31,5.111677e-31,5.111461e-31,5.111597e-31,5.111461e-31,5.111840e-31,5.111245e-31,5.111542e-31,5.111677e-31,5.111786e-31,5.111677e-31,5.111892e-31,5.111867e-31,5.111594e-31,5.111542e-31,5.111461e-31,5.111461e-31,5.111489e-31,5.111542e-31,5.111299e-31,5.111867e-31,5.111786e-31,5.111299e-31,1.202872e-12,1.203062e-12,1.203132e-12,1.203147e-12,1.203080e-12,1.203036e-12,1.203051e-12,1.202950e-12,1.203056e-12,1.203025e-12,1.203067e-12,1.201019e-12,1.202777e-12,1.202918e-12,1.198146e-12,1.202207e-12,1.202323e-12,1.202721e-12,1.202982e-12,1.201824e-12,1.203016e-12,1.203111e-12,1.203109e-12,1.203064e-12,1.202214e-12,1.203094e-12,1.056859e-07,1.069813e-07,1.068918e-07,1.069731e-07,1.067879e-07,9.925203e-08,1.065169e-07,1.067720e-07,9.567351e-08,1.061269e-07,1.068738e-07,1.002584e-07,1.067610e-07,1.069669e-07,1.020017e-07,1.054180e-07,1.061756e-07,9.844285e-08,1.040931e-07,1.043744e-07,1.052831e-07,1.062094e-07,1.033102e-07,1.064327e-07,1.068430e-07,1.067436e-07,1.064088e-07,1.040096e-07,1.067188e-07,5.449067e-06,2.706551e-06,5.836964e-06,3.695634e-06,5.801161e-06,5.833626e-06,3.451926e-06,5.762271e-06,4.397482e-06,5.673675e-06,5.758306e-06,3.997644e-06,5.560026e-06,5.793905e-06,4.525559e-06,5.752838e-06,5.831018e-06,5.168859e-06,5.356980e-06,5.582546e-06,4.978430e-06,5.640204e-06,5.102124e-06,2.601504e-05,9.496978e-06,3.058765e-05,1.358994e-05,3.008526e-05,2.710820e-05,3.054102e-05,1.249342e-05,2.956473e-05,1.764504e-05,2.846226e-05,2.951743e-05,1.532756e-05,2.717309e-05,1.355043e-05,2.998640e-05,1.852374e-05,2.944374e-05,1.020576e-05,3.050481e-05,2.341930e-05,2.510869e-05,2.741899e-05,2.183935e-05,2.806830e-05,2.283266e-05,5.046140e-05,1.499352e-05,6.507664e-05,2.169488e-05,6.326965e-05,4.041267e-05,6.489926e-05,1.996210e-05,6.149049e-05,3.179689e-05,6.107018e-05,4.349307e-05,4.785749e-05,5.461262e-05,3.951244e-05,5.657595e-05,4.188267e-05,6.643681e-05,1.701268e-05,9.193084e-05,2.527302e-05,8.849833e-05,3.780743e-05,9.155914e-05,2.338526e-05,8.530516e-05,3.873166e-05,8.451808e-05,7.331888e-05,4.973260e-05,7.654892e-05,5.304757e-05,7.487628e-05,1.748799e-05,1.078457e-04,4.236045e-05,9.790303e-05,4.905088e-17,3.745068e-17,4.379298e-19,1.966976e-19,5.755041e-15,2.728153e-14,1.389058e-16,3.278741e-16,4.960657e-15,6.570254e-15,9.327300e-19,1.487219e-05,5.521405e-06,1.366262e-05};

    double partial_densities_cpu[10] = {1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38};
    double point_weights_cpu[10] = {0.000000e+00,0.000000e+00,6.356219e-06,3.324887e-04,3.143648e-02,3.212402e-01,1.299464e-05,7.277725e-04,0.000000e+00,2.066700e+00};
    //double input[number_of_points];
    //for (int i=0; i<number_of_points; i++) {
    //	input[i]=0.001*i;
    //}

    cudaMemset(energy_gpu_in, 0, size);
    cudaMemset(factor_gpu_in, 0, size);
    cudaMemset(partial_density_gpu_accum, 0, size);
    cudaMemcpy(point_weights_gpu_in, point_weights_cpu, size, cudaMemcpyHostToDevice);
    cudaMemcpy(partial_density_gpu_in, partial_densities_cpu, size, cudaMemcpyHostToDevice);

    // Create the libxcproxy
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    // Allocate the host input vectors
    double *energy_cpu = (double *)malloc(size);
    double *factor_cpu = (double *)malloc(size);

    for (int i=0; i<iterations; i++) {
        dxyz_gpu_in.zero();
	dd1_gpu_in.zero();
        dd2_gpu_in.zero();

        dxyz_gpu_accum.zero();
        dd1_gpu_accum.zero();
	dd2_gpu_accum.zero();

        /////////////////////////////////
	// LIBXC VERSION
        printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
        
	gpu_accumulate_point_for_libxc<double,true,true,false><<<blocksPerGrid,threadsPerBlock>>> (point_weights_gpu_in,
    	    number_of_points, block_height,
	    partial_density_gpu_in, dxyz_gpu_in.data, dd1_gpu_in.data, dd2_gpu_in.data,
	    partial_density_gpu_accum, dxyz_gpu_accum.data, dd1_gpu_accum.data, dd2_gpu_accum.data);
	
	
        // Calculate exc_corr and y2a
        libxc_exchange_correlation_gpu<double, true, true, false> (&libxcProxy,
    	    energy_gpu_in,
	    factor_gpu_in,
	    number_of_points,
	    partial_density_gpu_accum,
	    dxyz_gpu_accum.data,
            dd1_gpu_accum.data,
	    dd2_gpu_accum.data);
	
        // Join the results.
        gpu_accumulate_energy_and_forces_from_libxc<double, true, true, false><<<blocksPerGrid, threadsPerBlock>>> (
    	    energy_gpu_in,
	    factor_gpu_in,
	    point_weights_gpu_in,
	    number_of_points,
	    partial_density_gpu_accum);
	

        // Copy the vectors from gpu to cpu
        err = cudaMemcpy(energy_cpu, energy_gpu_in, size, cudaMemcpyDeviceToHost);
	if (err != cudaSuccess)
        {
    	    printf("Failed to copy vector energy_gpu_in from device to host!\n");
    	    exit(EXIT_FAILURE);
	}

        err = cudaMemcpy(factor_cpu, factor_gpu_in, size, cudaMemcpyDeviceToHost);
	if (err != cudaSuccess)
        {
    	printf("Failed to copy vector factor_gpu_in from device to host!\n");
	    exit(EXIT_FAILURE);
        }

	///////////////////////////
	// Print libxc results
        printf("iteration %i\n",i);
	print_accumulate_point_data (NULL, NULL, NULL, energy_cpu,
	    factor_cpu, NULL, NULL, number_of_points);

        cudaMemset(energy_gpu_in, 0, size);
	cudaMemset(factor_gpu_in, 0, size);
        cudaMemset(partial_density_gpu_accum, 0, size);

    }

    ////////////////////////////
    // Free Memory CPU
    free(energy_cpu);
    free(factor_cpu);

    ///////////////////////////
    // Free memory GPU
    cudaFree (point_weights_gpu_in);
    cudaFree (partial_density_gpu_in);
    cudaFree (partial_density_gpu_accum);
    cudaFree (energy_gpu_in);
    cudaFree (factor_gpu_in);
#endif
}

void accumulate_data_for_libxc_test0009()
{
    // Este es el input.
    /*
    ==============================
    = Proxy input for libxc_cuda =
    ==============================
    number_of_points:221
    grad:[(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000001,-0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000001,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000001,0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000035,-0.000017,0.000026),(0.000009,0.000001,0.000028),(0.000013,0.000007,0.000010),(0.000003,0.000003,0.000001),(0.000002,0.000004,0.000005),(-0.000000,0.000017,-0.000003),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000008,0.000000,0.000008),(0.000002,0.000004,0.000002),(0.000007,-0.000007,0.000007),(0.000002,0.000005,0.000004),(0.000005,-0.000005,0.000009),(0.000005,-0.000009,0.000005),(0.000004,0.000004,0.000002),(0.000009,-0.000005,0.000005),(0.000002,0.000004,0.000007),(0.000003,-0.000003,0.000011),(0.000003,-0.000011,0.000003),(0.000006,0.000004,0.000001),(0.000010,-0.000003,0.000003),(0.000008,-0.000008,0.000004),(0.000005,0.000004,0.000005),(0.000008,-0.000004,0.000008),(0.000004,-0.000008,0.000008),(0.000010,0.000001,0.000003),(0.000003,0.000001,0.000010),(0.000009,-0.000001,0.000006),(0.000008,0.000002,0.000005),(0.000006,-0.000002,0.000010),(0.000005,0.000002,0.000008),(0.000025,0.000007,0.000024),(0.000003,0.000011,0.000002),(0.000026,-0.000025,0.000025),(0.000001,0.000019,0.000006),(0.000019,-0.000018,0.000034),(0.000055,-0.000034,0.000067),(0.000019,-0.000035,0.000019),(0.000007,0.000017,-0.000000),(0.000034,-0.000017,0.000018),(0.000001,0.000018,0.000015),(0.000010,-0.000008,0.000037),(0.000011,-0.000039,0.000010),(0.000013,0.000017,-0.000002),(0.000036,-0.000007,0.000008),(0.000025,-0.000013,0.000025),(0.000030,-0.000028,0.000012),(0.000012,0.000019,0.000010),(0.000029,-0.000010,0.000028),(0.000011,-0.000005,0.000017),(0.000013,-0.000029,0.000030),(0.000029,0.000008,0.000006),(0.000009,0.000007,0.000031),(0.000033,-0.000001,0.000018),(0.000022,0.000014,0.000010),(0.000020,-0.000002,0.000033),(0.000013,0.000014,0.000023),(0.000031,0.000025,0.000028),(-0.000001,0.000014,-0.000001),(0.000040,-0.000035,0.000037),(-0.000007,0.000036,-0.000002),(0.000026,-0.000020,0.000053),(0.000077,-0.000088,0.000098),(0.000028,-0.000053,0.000025),(0.000001,0.000031,-0.000009),(0.000053,-0.000018,0.000021),(0.000007,0.000042,0.000003),(0.000043,-0.000007,0.000040),(0.000036,0.000028,-0.000003),(0.000004,0.000027,0.000039),(0.000047,0.000011,0.000020),(0.000024,0.000037,0.000004),(0.000025,0.000010,0.000046),(0.000010,0.000037,0.000023),(0.000027,0.000054,0.000019),(-0.000008,0.000019,-0.000007),(0.000041,-0.000028,0.000034),(-0.000018,0.000055,-0.000013),(0.000021,-0.000008,0.000054),(0.000066,-0.000120,0.000090),(0.000024,-0.000052,0.000017),(-0.000008,0.000046,-0.000019),(0.000057,-0.000004,0.000011),(-0.000003,0.000069,-0.000010),(0.000044,0.000011,0.000037),(0.000048,0.000036,0.000009),(0.000018,0.000066,-0.000011),(0.000019,0.000034,0.000044),(-0.000001,0.000067,0.000014),(0.000023,0.000084,0.000011),(-0.000016,0.000035,-0.000016),(0.000037,-0.000014,0.000026),(-0.000009,0.000097,-0.000018),(0.000042,0.000035,0.000030),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000009,-0.000018,0.000016),(0.000005,0.000007,0.000001),(0.000011,0.000005,0.000018),]
    hess1:[(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000001,0.000001,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000002,0.000000),(0.000001,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000000,0.000001,0.000001),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000014,-0.000019,-0.000005),(-0.000011,-0.000016,0.000027),(0.000007,-0.000005,0.000001),(0.000003,0.000002,-0.000002),(-0.000002,0.000002,0.000003),(-0.000004,0.000095,0.000018),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,-0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,-0.000000),(0.000000,-0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000001),(0.000000,0.000000,0.000001),(0.000000,0.000001,0.000000),(0.000001,0.000000,-0.000000),(0.000001,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,-0.000000,0.000001),(-0.000000,-0.000000,0.000001),(-0.000000,0.000001,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,-0.000000),(0.000001,-0.000000,0.000000),(0.000000,-0.000000,0.000001),(0.000001,-0.000000,0.000000),(0.000001,-0.000000,0.000000),(0.000001,0.000000,-0.000000),(-0.000000,0.000001,0.000000),(-0.000000,0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,-0.000000,0.000001),(0.000000,0.000001,-0.000000),(0.000007,-0.000004,0.000007),(-0.000000,0.000006,-0.000000),(0.000005,0.000004,0.000004),(-0.000002,0.000003,0.000002),(0.000001,0.000001,0.000011),(0.000001,0.000011,0.000001),(0.000002,0.000003,-0.000002),(0.000011,0.000001,0.000001),(-0.000002,-0.000000,0.000008),(-0.000002,-0.000002,0.000016),(-0.000002,0.000016,-0.000002),(0.000007,0.000000,-0.000003),(0.000016,-0.000002,-0.000002),(0.000007,0.000007,-0.000001),(0.000003,0.000000,0.000002),(0.000007,-0.000002,0.000007),(-0.000001,0.000007,0.000007),(0.000014,-0.000004,-0.000002),(-0.000001,-0.000004,0.000015),(0.000013,-0.000003,0.000002),(0.000009,-0.000002,0.000001),(0.000003,-0.000003,0.000013),(0.000001,-0.000003,0.000009),(0.000006,-0.000021,0.000003),(-0.000001,0.000033,0.000004),(0.000003,-0.000001,0.000001),(-0.000012,0.000018,-0.000012),(-0.000009,-0.000012,0.000021),(0.000108,0.000012,0.000166),(-0.000008,0.000020,-0.000010),(-0.000008,0.000020,-0.000010),(0.000022,-0.000013,-0.000011),(-0.000016,0.000001,-0.000004),(-0.000017,-0.000021,0.000032),(-0.000017,0.000034,-0.000019),(-0.000002,0.000006,-0.000014),(0.000031,-0.000021,-0.000019),(0.000058,0.000034,0.000070),(0.000011,0.000006,-0.000017),(-0.000008,0.000002,-0.000012),(0.000010,-0.000019,0.000007),(0.000028,0.000035,0.000056),(-0.000016,0.000008,0.000010),(0.000021,-0.000019,-0.000019),(-0.000016,-0.000021,0.000022),(0.000023,-0.000023,-0.000008),(0.000007,-0.000011,-0.000014),(-0.000005,-0.000023,0.000021),(-0.000010,-0.000013,0.000005),(-0.000018,-0.000049,-0.000029),(0.000003,0.000100,0.000020),(-0.000023,-0.000037,-0.000030),(-0.000023,0.000058,-0.000029),(-0.000041,-0.000054,0.000001),(0.000149,0.000116,0.000241),(-0.000040,-0.000004,-0.000046),(-0.000022,0.000066,-0.000011),(0.000008,-0.000054,-0.000048),(-0.000032,0.000016,-0.000039),(-0.000012,-0.000062,-0.000021),(0.000003,-0.000041,-0.000050),(-0.000046,-0.000047,-0.000002),(0.000007,-0.000061,-0.000044),(-0.000016,-0.000018,-0.000045),(-0.000035,-0.000062,-0.000001),(-0.000038,-0.000023,-0.000025),(-0.000040,-0.000078,-0.000057),(0.000006,0.000207,0.000035),(-0.000058,-0.000088,-0.000072),(-0.000028,0.000128,-0.000030),(-0.000083,-0.000109,-0.000022),(0.000146,0.000282,0.000245),(-0.000084,-0.000038,-0.000096),(-0.000027,0.000142,-0.000004),(-0.000007,-0.000109,-0.000095),(-0.000047,0.000050,-0.000053),(-0.000038,-0.000118,-0.000055),(-0.000003,-0.000105,-0.000083),(-0.000026,-0.000015,-0.000070),(-0.000070,-0.000109,-0.000020),(-0.000064,-0.000024,-0.000042),(-0.000057,-0.000111,-0.000077),(-0.000002,0.000337,0.000033),(-0.000100,-0.000144,-0.000121),(-0.000057,0.000094,-0.000062),(-0.000065,-0.000183,-0.000088),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(-0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(0.000000,-0.000000,0.000000),(0.000000,-0.000000,0.000000),(-0.000004,0.000013,0.000007),(0.000001,0.000011,-0.000001),(-0.000000,-0.000009,0.000014),]
    hess2:[(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000001,0.000001,-0.000001),(-0.000000,0.000001,-0.000000),(-0.000001,0.000000,-0.000001),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000001),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000017,0.000027,-0.000011),(0.000003,0.000011,0.000005),(0.000010,0.000011,0.000009),(0.000005,0.000000,0.000001),(0.000003,0.000002,0.000007),(-0.000028,0.000011,-0.000050),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(0.000001,0.000010,0.000001),(0.000002,0.000001,0.000002),(-0.000008,0.000008,-0.000008),(0.000003,0.000002,0.000006),(-0.000005,0.000008,-0.000008),(-0.000008,0.000005,-0.000008),(0.000006,0.000001,0.000003),(-0.000008,0.000008,-0.000004),(0.000002,0.000002,0.000007),(-0.000002,0.000006,-0.000006),(-0.000006,0.000002,-0.000006),(0.000007,0.000001,0.000002),(-0.000005,0.000005,-0.000001),(-0.000011,0.000005,-0.000005),(0.000005,0.000005,0.000005),(-0.000005,0.000011,-0.000005),(-0.000005,0.000005,-0.000011),(0.000002,0.000005,0.000001),(0.000001,0.000006,0.000002),(-0.000002,0.000010,-0.000001),(0.000005,0.000007,0.000003),(-0.000001,0.000010,-0.000002),(0.000003,0.000008,0.000004),(0.000011,0.000022,0.000012),(-0.000008,0.000006,-0.000012),(-0.000021,0.000022,-0.000020),(0.000007,-0.000005,0.000015),(-0.000010,0.000022,-0.000020),(-0.000080,0.000147,-0.000094),(-0.000022,0.000011,-0.000021),(0.000013,-0.000005,0.000001),(-0.000019,0.000020,-0.000008),(0.000007,-0.000006,0.000026),(-0.000000,0.000012,-0.000008),(-0.000013,0.000002,-0.000012),(0.000022,-0.000008,0.000003),(-0.000006,0.000008,0.000002),(-0.000056,0.000071,-0.000057),(-0.000029,0.000011,-0.000009),(0.000020,0.000001,0.000020),(-0.000009,0.000028,-0.000008),(-0.000036,0.000043,-0.000048),(-0.000012,0.000012,-0.000029),(0.000016,0.000004,0.000008),(0.000007,0.000008,0.000015),(0.000002,0.000021,0.000003),(0.000022,0.000007,0.000014),(0.000002,0.000023,0.000002),(0.000014,0.000010,0.000022),(0.000034,0.000015,0.000036),(-0.000039,0.000016,-0.000054),(-0.000021,0.000024,-0.000017),(-0.000001,-0.000014,0.000013),(-0.000003,0.000022,-0.000013),(-0.000189,0.000199,-0.000226),(-0.000022,0.000007,-0.000018),(0.000009,-0.000009,-0.000019),(-0.000014,0.000018,0.000003),(0.000035,-0.000013,0.000032),(0.000002,0.000031,0.000005),(0.000045,-0.000013,0.000021),(0.000021,-0.000005,0.000046),(0.000022,0.000016,0.000021),(0.000049,-0.000008,0.000029),(0.000017,0.000021,0.000023),(0.000032,-0.000003,0.000050),(0.000060,0.000018,0.000061),(-0.000067,0.000023,-0.000096),(-0.000019,0.000026,-0.000011),(-0.000014,-0.000012,0.000008),(0.000008,0.000023,-0.000004),(-0.000262,0.000177,-0.000321),(-0.000021,0.000001,-0.000012),(0.000009,-0.000006,-0.000047),(-0.000007,0.000016,0.000017),(0.000050,-0.000013,0.000041),(0.000016,0.000038,0.000021),(0.000046,0.000016,0.000040),(0.000077,-0.000010,0.000040),(0.000036,0.000023,0.000049),(0.000048,-0.000006,0.000079),(0.000085,0.000042,0.000083),(-0.000070,0.000022,-0.000113),(-0.000028,0.000039,-0.000017),(0.000072,0.000003,0.000055),(0.000023,0.000061,0.000029),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(0.000000,0.000000,0.000000),(-0.000000,0.000000,-0.000000),(-0.000000,0.000000,-0.000000),(-0.000011,0.000010,-0.000019),(0.000004,0.000001,-0.000003),(0.000006,0.000014,0.000009),]
    dens:[1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38,6.815741e-37,2.776831e-36,1.143339e-34,3.467837e-35,2.173183e-36,2.919116e-35,3.249745e-13,1.280894e-13,2.872959e-13,5.841356e-14,1.052731e-14,4.778827e-14,2.419135e-15,1.127769e-13,4.739891e-14,2.618893e-13,3.192557e-15,6.648584e-15,4.077459e-07,2.149901e-07,3.746791e-07,1.251948e-07,3.841547e-08,1.084211e-07,3.515827e-07,1.679403e-08,2.794462e-08,3.479711e-05,2.007635e-05,1.120590e-05,2.301993e-06,3.572237e-06,1.566220e-05,5.111461e-31,5.111677e-31,5.111461e-31,5.111597e-31,5.111461e-31,5.111840e-31,5.111245e-31,5.111542e-31,5.111677e-31,5.111786e-31,5.111677e-31,5.111892e-31,5.111867e-31,5.111594e-31,5.111542e-31,5.111461e-31,5.111461e-31,5.111489e-31,5.111542e-31,5.111299e-31,5.111867e-31,5.111786e-31,5.111299e-31,1.202872e-12,1.203062e-12,1.203132e-12,1.203147e-12,1.203080e-12,1.203036e-12,1.203051e-12,1.202950e-12,1.203056e-12,1.203025e-12,1.203067e-12,1.201019e-12,1.202777e-12,1.202918e-12,1.198146e-12,1.202207e-12,1.202323e-12,1.202721e-12,1.202982e-12,1.201824e-12,1.203016e-12,1.203111e-12,1.203109e-12,1.203064e-12,1.202214e-12,1.203094e-12,1.056859e-07,1.069813e-07,1.068918e-07,1.069731e-07,1.067879e-07,9.925203e-08,1.065169e-07,1.067720e-07,9.567351e-08,1.061269e-07,1.068738e-07,1.002584e-07,1.067610e-07,1.069669e-07,1.020017e-07,1.054180e-07,1.061756e-07,9.844285e-08,1.040931e-07,1.043744e-07,1.052831e-07,1.062094e-07,1.033102e-07,1.064327e-07,1.068430e-07,1.067436e-07,1.064088e-07,1.040096e-07,1.067188e-07,5.449067e-06,2.706551e-06,5.836964e-06,3.695634e-06,5.801161e-06,5.833626e-06,3.451926e-06,5.762271e-06,4.397482e-06,5.673675e-06,5.758306e-06,3.997644e-06,5.560026e-06,5.793905e-06,4.525559e-06,5.752838e-06,5.831018e-06,5.168859e-06,5.356980e-06,5.582546e-06,4.978430e-06,5.640204e-06,5.102124e-06,2.601504e-05,9.496978e-06,3.058765e-05,1.358994e-05,3.008526e-05,2.710820e-05,3.054102e-05,1.249342e-05,2.956473e-05,1.764504e-05,2.846226e-05,2.951743e-05,1.532756e-05,2.717309e-05,1.355043e-05,2.998640e-05,1.852374e-05,2.944374e-05,1.020576e-05,3.050481e-05,2.341930e-05,2.510869e-05,2.741899e-05,2.183935e-05,2.806830e-05,2.283266e-05,5.046140e-05,1.499352e-05,6.507664e-05,2.169488e-05,6.326965e-05,4.041267e-05,6.489926e-05,1.996210e-05,6.149049e-05,3.179689e-05,6.107018e-05,4.349307e-05,4.785749e-05,5.461262e-05,3.951244e-05,5.657595e-05,4.188267e-05,6.643681e-05,1.701268e-05,9.193084e-05,2.527302e-05,8.849833e-05,3.780743e-05,9.155914e-05,2.338526e-05,8.530516e-05,3.873166e-05,8.451808e-05,7.331888e-05,4.973260e-05,7.654892e-05,5.304757e-05,7.487628e-05,1.748799e-05,1.078457e-04,4.236045e-05,9.790303e-05,4.905088e-17,3.745068e-17,4.379298e-19,1.966976e-19,5.755041e-15,2.728153e-14,1.389058e-16,3.278741e-16,4.960657e-15,6.570254e-15,9.327300e-19,1.487219e-05,5.521405e-06,1.366262e-05,]
    contracted_grad:[0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.631121e-24,4.275903e-25,2.068908e-24,9.222840e-26,3.229578e-27,6.229285e-26,1.811449e-28,3.334638e-25,6.130454e-26,1.726994e-24,3.120054e-28,1.313191e-27,1.252649e-12,3.835113e-13,1.071992e-12,1.400556e-13,1.523680e-14,1.070453e-13,9.533463e-13,3.176699e-15,8.346576e-15,2.204637e-09,8.742831e-10,3.206804e-10,2.002568e-11,4.366787e-11,3.086138e-10,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,3.370783e-23,3.372360e-23,3.372715e-23,3.372821e-23,3.372406e-23,3.372065e-23,3.372238e-23,3.371434e-23,3.372298e-23,3.372095e-23,3.372386e-23,3.357765e-23,3.370100e-23,3.371264e-23,3.338174e-23,3.366109e-23,3.366948e-23,3.369719e-23,3.371641e-23,3.363387e-23,3.371924e-23,3.372586e-23,3.372542e-23,3.372177e-23,3.366073e-23,3.372460e-23,1.019537e-13,1.054808e-13,1.052235e-13,1.054570e-13,1.049289e-13,8.677356e-14,1.041766e-13,1.048868e-13,7.931585e-14,1.031177e-13,1.051718e-13,8.897470e-14,1.048535e-13,1.054386e-13,9.293591e-14,1.012597e-13,1.032553e-13,8.502833e-14,9.791433e-14,9.860958e-14,1.009087e-13,1.033391e-13,9.601215e-14,1.039444e-13,1.050876e-13,1.048057e-13,1.038799e-13,9.771355e-14,1.047368e-13,1.162748e-10,2.334933e-11,1.424700e-10,4.534937e-11,1.397742e-10,1.422207e-10,3.933528e-11,1.369135e-10,6.691021e-11,1.306937e-10,1.366455e-10,5.385416e-11,1.231582e-10,1.392328e-10,7.169444e-11,1.362370e-10,1.420250e-10,1.005558e-10,1.108657e-10,1.246111e-10,9.106069e-11,1.284195e-10,9.712042e-11,1.212137e-09,1.356080e-10,1.951985e-09,3.867117e-10,1.850601e-09,8.758271e-09,1.942269e-09,3.268466e-10,1.751971e-09,5.571538e-10,1.559754e-09,1.742656e-09,4.531791e-10,1.365493e-09,1.377643e-09,1.831493e-09,6.010568e-10,1.729588e-09,4.316582e-10,1.934755e-09,9.375115e-10,1.104771e-09,1.400412e-09,8.067573e-10,1.497223e-09,8.842579e-10,2.398833e-09,2.080791e-10,4.198249e-09,1.379833e-09,3.853848e-09,2.323771e-08,4.159398e-09,1.061023e-09,3.564113e-09,1.848764e-09,3.496477e-09,2.089923e-09,2.246474e-09,2.720921e-09,1.991728e-09,2.908715e-09,2.046485e-09,3.957297e-09,4.837907e-10,3.625368e-09,3.493492e-09,3.473267e-09,2.693226e-08,3.592708e-09,2.585125e-09,3.433550e-09,4.815363e-09,3.420134e-09,3.636069e-09,4.738457e-09,3.512618e-09,4.680167e-09,7.756806e-09,1.712467e-09,2.265633e-09,9.828216e-09,3.841888e-09,8.604033e-32,5.062453e-32,7.974179e-36,1.646879e-36,9.898778e-28,2.081598e-26,6.652570e-31,3.592657e-30,7.397754e-28,1.283103e-27,3.536233e-35,6.664909e-10,7.040826e-11,4.714138e-10,]
    ==============================
    */

    // Hay que llamar a esta funcion y los parametros tiene que estar en memoria de la placa.
/*
template<class T, bool compute_energy, bool compute_factor, bool lda>
    void libxc_exchange_correlation_gpu (LibxcProxy<T, WIDTH>* libxcProxy,
	T* energy_gpu,
	T* factor_gpu,
	uint points,
	T* accumulated_density_gpu,
	G2G::vec_type<T,WIDTH>* dxyz_gpu,
        G2G::vec_type<T,WIDTH>* dd1_gpu,
	G2G::vec_type<T,WIDTH>* dd2_gpu)
{
    printf("libxc_exchage_correlation_gpu (...) \n");
*/

    ////////////////////////////////
    // PARAMS SETUP
#if FULL_DOUBLE
    int number_of_points = 221;
    double dens_cpu[221] = {1.016692e-33,2.333626e-34,8.367814e-34,6.744978e-35,4.493371e-36,4.396106e-37,1.908333e-34,4.848228e-35,7.228556e-34,1.717567e-38,6.815741e-37,2.776831e-36,1.143339e-34,3.467837e-35,2.173183e-36,2.919116e-35,3.249745e-13,1.280894e-13,2.872959e-13,5.841356e-14,1.052731e-14,4.778827e-14,2.419135e-15,1.127769e-13,4.739891e-14,2.618893e-13,3.192557e-15,6.648584e-15,4.077459e-07,2.149901e-07,3.746791e-07,1.251948e-07,3.841547e-08,1.084211e-07,3.515827e-07,1.679403e-08,2.794462e-08,3.479711e-05,2.007635e-05,1.120590e-05,2.301993e-06,3.572237e-06,1.566220e-05,5.111461e-31,5.111677e-31,5.111461e-31,5.111597e-31,5.111461e-31,5.111840e-31,5.111245e-31,5.111542e-31,5.111677e-31,5.111786e-31,5.111677e-31,5.111892e-31,5.111867e-31,5.111594e-31,5.111542e-31,5.111461e-31,5.111461e-31,5.111489e-31,5.111542e-31,5.111299e-31,5.111867e-31,5.111786e-31,5.111299e-31,1.202872e-12,1.203062e-12,1.203132e-12,1.203147e-12,1.203080e-12,1.203036e-12,1.203051e-12,1.202950e-12,1.203056e-12,1.203025e-12,1.203067e-12,1.201019e-12,1.202777e-12,1.202918e-12,1.198146e-12,1.202207e-12,1.202323e-12,1.202721e-12,1.202982e-12,1.201824e-12,1.203016e-12,1.203111e-12,1.203109e-12,1.203064e-12,1.202214e-12,1.203094e-12,1.056859e-07,1.069813e-07,1.068918e-07,1.069731e-07,1.067879e-07,9.925203e-08,1.065169e-07,1.067720e-07,9.567351e-08,1.061269e-07,1.068738e-07,1.002584e-07,1.067610e-07,1.069669e-07,1.020017e-07,1.054180e-07,1.061756e-07,9.844285e-08,1.040931e-07,1.043744e-07,1.052831e-07,1.062094e-07,1.033102e-07,1.064327e-07,1.068430e-07,1.067436e-07,1.064088e-07,1.040096e-07,1.067188e-07,5.449067e-06,2.706551e-06,5.836964e-06,3.695634e-06,5.801161e-06,5.833626e-06,3.451926e-06,5.762271e-06,4.397482e-06,5.673675e-06,5.758306e-06,3.997644e-06,5.560026e-06,5.793905e-06,4.525559e-06,5.752838e-06,5.831018e-06,5.168859e-06,5.356980e-06,5.582546e-06,4.978430e-06,5.640204e-06,5.102124e-06,2.601504e-05,9.496978e-06,3.058765e-05,1.358994e-05,3.008526e-05,2.710820e-05,3.054102e-05,1.249342e-05,2.956473e-05,1.764504e-05,2.846226e-05,2.951743e-05,1.532756e-05,2.717309e-05,1.355043e-05,2.998640e-05,1.852374e-05,2.944374e-05,1.020576e-05,3.050481e-05,2.341930e-05,2.510869e-05,2.741899e-05,2.183935e-05,2.806830e-05,2.283266e-05,5.046140e-05,1.499352e-05,6.507664e-05,2.169488e-05,6.326965e-05,4.041267e-05,6.489926e-05,1.996210e-05,6.149049e-05,3.179689e-05,6.107018e-05,4.349307e-05,4.785749e-05,5.461262e-05,3.951244e-05,5.657595e-05,4.188267e-05,6.643681e-05,1.701268e-05,9.193084e-05,2.527302e-05,8.849833e-05,3.780743e-05,9.155914e-05,2.338526e-05,8.530516e-05,3.873166e-05,8.451808e-05,7.331888e-05,4.973260e-05,7.654892e-05,5.304757e-05,7.487628e-05,1.748799e-05,1.078457e-04,4.236045e-05,9.790303e-05,4.905088e-17,3.745068e-17,4.379298e-19,1.966976e-19,5.755041e-15,2.728153e-14,1.389058e-16,3.278741e-16,4.960657e-15,6.570254e-15,9.327300e-19,1.487219e-05,5.521405e-06,1.366262e-05};
    double contracted_gradient_cpu[221] = {0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,2.631121e-24,4.275903e-25,2.068908e-24,9.222840e-26,3.229578e-27,6.229285e-26,1.811449e-28,3.334638e-25,6.130454e-26,1.726994e-24,3.120054e-28,1.313191e-27,1.252649e-12,3.835113e-13,1.071992e-12,1.400556e-13,1.523680e-14,1.070453e-13,9.533463e-13,3.176699e-15,8.346576e-15,2.204637e-09,8.742831e-10,3.206804e-10,2.002568e-11,4.366787e-11,3.086138e-10,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00,3.370783e-23,3.372360e-23,3.372715e-23,3.372821e-23,3.372406e-23,3.372065e-23,3.372238e-23,3.371434e-23,3.372298e-23,3.372095e-23,3.372386e-23,3.357765e-23,3.370100e-23,3.371264e-23,3.338174e-23,3.366109e-23,3.366948e-23,3.369719e-23,3.371641e-23,3.363387e-23,3.371924e-23,3.372586e-23,3.372542e-23,3.372177e-23,3.366073e-23,3.372460e-23,1.019537e-13,1.054808e-13,1.052235e-13,1.054570e-13,1.049289e-13,8.677356e-14,1.041766e-13,1.048868e-13,7.931585e-14,1.031177e-13,1.051718e-13,8.897470e-14,1.048535e-13,1.054386e-13,9.293591e-14,1.012597e-13,1.032553e-13,8.502833e-14,9.791433e-14,9.860958e-14,1.009087e-13,1.033391e-13,9.601215e-14,1.039444e-13,1.050876e-13,1.048057e-13,1.038799e-13,9.771355e-14,1.047368e-13,1.162748e-10,2.334933e-11,1.424700e-10,4.534937e-11,1.397742e-10,1.422207e-10,3.933528e-11,1.369135e-10,6.691021e-11,1.306937e-10,1.366455e-10,5.385416e-11,1.231582e-10,1.392328e-10,7.169444e-11,1.362370e-10,1.420250e-10,1.005558e-10,1.108657e-10,1.246111e-10,9.106069e-11,1.284195e-10,9.712042e-11,1.212137e-09,1.356080e-10,1.951985e-09,3.867117e-10,1.850601e-09,8.758271e-09,1.942269e-09,3.268466e-10,1.751971e-09,5.571538e-10,1.559754e-09,1.742656e-09,4.531791e-10,1.365493e-09,1.377643e-09,1.831493e-09,6.010568e-10,1.729588e-09,4.316582e-10,1.934755e-09,9.375115e-10,1.104771e-09,1.400412e-09,8.067573e-10,1.497223e-09,8.842579e-10,2.398833e-09,2.080791e-10,4.198249e-09,1.379833e-09,3.853848e-09,2.323771e-08,4.159398e-09,1.061023e-09,3.564113e-09,1.848764e-09,3.496477e-09,2.089923e-09,2.246474e-09,2.720921e-09,1.991728e-09,2.908715e-09,2.046485e-09,3.957297e-09,4.837907e-10,3.625368e-09,3.493492e-09,3.473267e-09,2.693226e-08,3.592708e-09,2.585125e-09,3.433550e-09,4.815363e-09,3.420134e-09,3.636069e-09,4.738457e-09,3.512618e-09,4.680167e-09,7.756806e-09,1.712467e-09,2.265633e-09,9.828216e-09,3.841888e-09,8.604033e-32,5.062453e-32,7.974179e-36,1.646879e-36,9.898778e-28,2.081598e-26,6.652570e-31,3.592657e-30,7.397754e-28,1.283103e-27,3.536233e-35,6.664909e-10,7.040826e-11,4.714138e-10};

    G2G::vec_type<double,4> grad[221] = {G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000001,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000001,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000001,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000035,-0.000017,0.000026,0),G2G::vec_type<double,4>(0.000009,0.000001,0.000028,0),G2G::vec_type<double,4>(0.000013,0.000007,0.000010,0),G2G::vec_type<double,4>(0.000003,0.000003,0.000001,0),G2G::vec_type<double,4>(0.000002,0.000004,0.000005,0),G2G::vec_type<double,4>(-0.000000,0.000017,-0.000003,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000008,0.000000,0.000008,0),G2G::vec_type<double,4>(0.000002,0.000004,0.000002,0),G2G::vec_type<double,4>(0.000007,-0.000007,0.000007,0),G2G::vec_type<double,4>(0.000002,0.000005,0.000004,0),G2G::vec_type<double,4>(0.000005,-0.000005,0.000009,0),G2G::vec_type<double,4>(0.000005,-0.000009,0.000005,0),G2G::vec_type<double,4>(0.000004,0.000004,0.000002,0),G2G::vec_type<double,4>(0.000009,-0.000005,0.000005,0),G2G::vec_type<double,4>(0.000002,0.000004,0.000007,0),G2G::vec_type<double,4>(0.000003,-0.000003,0.000011,0),G2G::vec_type<double,4>(0.000003,-0.000011,0.000003,0),G2G::vec_type<double,4>(0.000006,0.000004,0.000001,0),G2G::vec_type<double,4>(0.000010,-0.000003,0.000003,0),G2G::vec_type<double,4>(0.000008,-0.000008,0.000004,0),G2G::vec_type<double,4>(0.000005,0.000004,0.000005,0),G2G::vec_type<double,4>(0.000008,-0.000004,0.000008,0),G2G::vec_type<double,4>(0.000004,-0.000008,0.000008,0),G2G::vec_type<double,4>(0.000010,0.000001,0.000003,0),G2G::vec_type<double,4>(0.000003,0.000001,0.000010,0),G2G::vec_type<double,4>(0.000009,-0.000001,0.000006,0),G2G::vec_type<double,4>(0.000008,0.000002,0.000005,0),G2G::vec_type<double,4>(0.000006,-0.000002,0.000010,0),G2G::vec_type<double,4>(0.000005,0.000002,0.000008,0),G2G::vec_type<double,4>(0.000025,0.000007,0.000024,0),G2G::vec_type<double,4>(0.000003,0.000011,0.000002,0),G2G::vec_type<double,4>(0.000026,-0.000025,0.000025,0),G2G::vec_type<double,4>(0.000001,0.000019,0.000006,0),G2G::vec_type<double,4>(0.000019,-0.000018,0.000034,0),G2G::vec_type<double,4>(0.000055,-0.000034,0.000067,0),G2G::vec_type<double,4>(0.000019,-0.000035,0.000019,0),G2G::vec_type<double,4>(0.000007,0.000017,-0.000000,0),G2G::vec_type<double,4>(0.000034,-0.000017,0.000018,0),G2G::vec_type<double,4>(0.000001,0.000018,0.000015,0),G2G::vec_type<double,4>(0.000010,-0.000008,0.000037,0),G2G::vec_type<double,4>(0.000011,-0.000039,0.000010,0),G2G::vec_type<double,4>(0.000013,0.000017,-0.000002,0),G2G::vec_type<double,4>(0.000036,-0.000007,0.000008,0),G2G::vec_type<double,4>(0.000025,-0.000013,0.000025,0),G2G::vec_type<double,4>(0.000030,-0.000028,0.000012,0),G2G::vec_type<double,4>(0.000012,0.000019,0.000010,0),G2G::vec_type<double,4>(0.000029,-0.000010,0.000028,0),G2G::vec_type<double,4>(0.000011,-0.000005,0.000017,0),G2G::vec_type<double,4>(0.000013,-0.000029,0.000030,0),G2G::vec_type<double,4>(0.000029,0.000008,0.000006,0),G2G::vec_type<double,4>(0.000009,0.000007,0.000031,0),G2G::vec_type<double,4>(0.000033,-0.000001,0.000018,0),G2G::vec_type<double,4>(0.000022,0.000014,0.000010,0),G2G::vec_type<double,4>(0.000020,-0.000002,0.000033,0),G2G::vec_type<double,4>(0.000013,0.000014,0.000023,0),G2G::vec_type<double,4>(0.000031,0.000025,0.000028,0),G2G::vec_type<double,4>(-0.000001,0.000014,-0.000001,0),G2G::vec_type<double,4>(0.000040,-0.000035,0.000037,0),G2G::vec_type<double,4>(-0.000007,0.000036,-0.000002,0),G2G::vec_type<double,4>(0.000026,-0.000020,0.000053,0),G2G::vec_type<double,4>(0.000077,-0.000088,0.000098,0),G2G::vec_type<double,4>(0.000028,-0.000053,0.000025,0),G2G::vec_type<double,4>(0.000001,0.000031,-0.000009,0),G2G::vec_type<double,4>(0.000053,-0.000018,0.000021,0),G2G::vec_type<double,4>(0.000007,0.000042,0.000003,0),G2G::vec_type<double,4>(0.000043,-0.000007,0.000040,0),G2G::vec_type<double,4>(0.000036,0.000028,-0.000003,0),G2G::vec_type<double,4>(0.000004,0.000027,0.000039,0),G2G::vec_type<double,4>(0.000047,0.000011,0.000020,0),G2G::vec_type<double,4>(0.000024,0.000037,0.000004,0),G2G::vec_type<double,4>(0.000025,0.000010,0.000046,0),G2G::vec_type<double,4>(0.000010,0.000037,0.000023,0),G2G::vec_type<double,4>(0.000027,0.000054,0.000019,0),G2G::vec_type<double,4>(-0.000008,0.000019,-0.000007,0),G2G::vec_type<double,4>(0.000041,-0.000028,0.000034,0),G2G::vec_type<double,4>(-0.000018,0.000055,-0.000013,0),G2G::vec_type<double,4>(0.000021,-0.000008,0.000054,0),G2G::vec_type<double,4>(0.000066,-0.000120,0.000090,0),G2G::vec_type<double,4>(0.000024,-0.000052,0.000017,0),G2G::vec_type<double,4>(-0.000008,0.000046,-0.000019,0),G2G::vec_type<double,4>(0.000057,-0.000004,0.000011,0),G2G::vec_type<double,4>(-0.000003,0.000069,-0.000010,0),G2G::vec_type<double,4>(0.000044,0.000011,0.000037,0),G2G::vec_type<double,4>(0.000048,0.000036,0.000009,0),G2G::vec_type<double,4>(0.000018,0.000066,-0.000011,0),G2G::vec_type<double,4>(0.000019,0.000034,0.000044,0),G2G::vec_type<double,4>(-0.000001,0.000067,0.000014,0),G2G::vec_type<double,4>(0.000023,0.000084,0.000011,0),G2G::vec_type<double,4>(-0.000016,0.000035,-0.000016,0),G2G::vec_type<double,4>(0.000037,-0.000014,0.000026,0),G2G::vec_type<double,4>(-0.000009,0.000097,-0.000018,0),G2G::vec_type<double,4>(0.000042,0.000035,0.000030,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000009,-0.000018,0.000016,0),G2G::vec_type<double,4>(0.000005,0.000007,0.0000010,0),G2G::vec_type<double,4>(0.000011,0.000005,0.000018,0)};
    G2G::vec_type<double,4> hess1[221] = {G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000001,0.000001,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000002,0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000001,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000014,-0.000019,-0.000005,0),G2G::vec_type<double,4>(-0.000011,-0.000016,0.000027,0),G2G::vec_type<double,4>(0.000007,-0.000005,0.000001,0),G2G::vec_type<double,4>(0.000003,0.000002,-0.000002,0),G2G::vec_type<double,4>(-0.000002,0.000002,0.000003,0),G2G::vec_type<double,4>(-0.000004,0.000095,0.000018,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000001,0.000000,0),G2G::vec_type<double,4>(0.000001,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000001,0.000000,0),G2G::vec_type<double,4>(0.000001,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000001,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(-0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(-0.000000,0.000001,-0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(0.000001,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000001,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000001,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000001,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000001,0),G2G::vec_type<double,4>(0.000000,0.000001,-0.000000,0),G2G::vec_type<double,4>(0.000007,-0.000004,0.000007,0),G2G::vec_type<double,4>(-0.000000,0.000006,-0.000000,0),G2G::vec_type<double,4>(0.000005,0.000004,0.000004,0),G2G::vec_type<double,4>(-0.000002,0.000003,0.000002,0),G2G::vec_type<double,4>(0.000001,0.000001,0.000011,0),G2G::vec_type<double,4>(0.000001,0.000011,0.000001,0),G2G::vec_type<double,4>(0.000002,0.000003,-0.000002,0),G2G::vec_type<double,4>(0.000011,0.000001,0.000001,0),G2G::vec_type<double,4>(-0.000002,-0.000000,0.000008,0),G2G::vec_type<double,4>(-0.000002,-0.000002,0.000016,0),G2G::vec_type<double,4>(-0.000002,0.000016,-0.000002,0),G2G::vec_type<double,4>(0.000007,0.000000,-0.000003,0),G2G::vec_type<double,4>(0.000016,-0.000002,-0.000002,0),G2G::vec_type<double,4>(0.000007,0.000007,-0.000001,0),G2G::vec_type<double,4>(0.000003,0.000000,0.000002,0),G2G::vec_type<double,4>(0.000007,-0.000002,0.000007,0),G2G::vec_type<double,4>(-0.000001,0.000007,0.000007,0),G2G::vec_type<double,4>(0.000014,-0.000004,-0.000002,0),G2G::vec_type<double,4>(-0.000001,-0.000004,0.000015,0),G2G::vec_type<double,4>(0.000013,-0.000003,0.000002,0),G2G::vec_type<double,4>(0.000009,-0.000002,0.000001,0),G2G::vec_type<double,4>(0.000003,-0.000003,0.000013,0),G2G::vec_type<double,4>(0.000001,-0.000003,0.000009,0),G2G::vec_type<double,4>(0.000006,-0.000021,0.000003,0),G2G::vec_type<double,4>(-0.000001,0.000033,0.000004,0),G2G::vec_type<double,4>(0.000003,-0.000001,0.000001,0),G2G::vec_type<double,4>(-0.000012,0.000018,-0.000012,0),G2G::vec_type<double,4>(-0.000009,-0.000012,0.000021,0),G2G::vec_type<double,4>(0.000108,0.000012,0.000166,0),G2G::vec_type<double,4>(-0.000008,0.000020,-0.000010,0),G2G::vec_type<double,4>(-0.000008,0.000020,-0.000010,0),G2G::vec_type<double,4>(0.000022,-0.000013,-0.000011,0),G2G::vec_type<double,4>(-0.000016,0.000001,-0.000004,0),G2G::vec_type<double,4>(-0.000017,-0.000021,0.000032,0),G2G::vec_type<double,4>(-0.000017,0.000034,-0.000019,0),G2G::vec_type<double,4>(-0.000002,0.000006,-0.000014,0),G2G::vec_type<double,4>(0.000031,-0.000021,-0.000019,0),G2G::vec_type<double,4>(0.000058,0.000034,0.000070,0),G2G::vec_type<double,4>(0.000011,0.000006,-0.000017,0),G2G::vec_type<double,4>(-0.000008,0.000002,-0.000012,0),G2G::vec_type<double,4>(0.000010,-0.000019,0.000007,0),G2G::vec_type<double,4>(0.000028,0.000035,0.000056,0),G2G::vec_type<double,4>(-0.000016,0.000008,0.000010,0),G2G::vec_type<double,4>(0.000021,-0.000019,-0.000019,0),G2G::vec_type<double,4>(-0.000016,-0.000021,0.000022,0),G2G::vec_type<double,4>(0.000023,-0.000023,-0.000008,0),G2G::vec_type<double,4>(0.000007,-0.000011,-0.000014,0),G2G::vec_type<double,4>(-0.000005,-0.000023,0.000021,0),G2G::vec_type<double,4>(-0.000010,-0.000013,0.000005,0),G2G::vec_type<double,4>(-0.000018,-0.000049,-0.000029,0),G2G::vec_type<double,4>(0.000003,0.000100,0.000020,0),G2G::vec_type<double,4>(-0.000023,-0.000037,-0.000030,0),G2G::vec_type<double,4>(-0.000023,0.000058,-0.000029,0),G2G::vec_type<double,4>(-0.000041,-0.000054,0.000001,0),G2G::vec_type<double,4>(0.000149,0.000116,0.000241,0),G2G::vec_type<double,4>(-0.000040,-0.000004,-0.000046,0),G2G::vec_type<double,4>(-0.000022,0.000066,-0.000011,0),G2G::vec_type<double,4>(0.000008,-0.000054,-0.000048,0),G2G::vec_type<double,4>(-0.000032,0.000016,-0.000039,0),G2G::vec_type<double,4>(-0.000012,-0.000062,-0.000021,0),G2G::vec_type<double,4>(0.000003,-0.000041,-0.000050,0),G2G::vec_type<double,4>(-0.000046,-0.000047,-0.000002,0),G2G::vec_type<double,4>(0.000007,-0.000061,-0.000044,0),G2G::vec_type<double,4>(-0.000016,-0.000018,-0.000045,0),G2G::vec_type<double,4>(-0.000035,-0.000062,-0.000001,0),G2G::vec_type<double,4>(-0.000038,-0.000023,-0.000025,0),G2G::vec_type<double,4>(-0.000040,-0.000078,-0.000057,0),G2G::vec_type<double,4>(0.000006,0.000207,0.000035,0),G2G::vec_type<double,4>(-0.000058,-0.000088,-0.000072,0),G2G::vec_type<double,4>(-0.000028,0.000128,-0.000030,0),G2G::vec_type<double,4>(-0.000083,-0.000109,-0.000022,0),G2G::vec_type<double,4>(0.000146,0.000282,0.000245,0),G2G::vec_type<double,4>(-0.000084,-0.000038,-0.000096,0),G2G::vec_type<double,4>(-0.000027,0.000142,-0.000004,0),G2G::vec_type<double,4>(-0.000007,-0.000109,-0.000095,0),G2G::vec_type<double,4>(-0.000047,0.000050,-0.000053,0),G2G::vec_type<double,4>(-0.000038,-0.000118,-0.000055,0),G2G::vec_type<double,4>(-0.000003,-0.000105,-0.000083,0),G2G::vec_type<double,4>(-0.000026,-0.000015,-0.000070,0),G2G::vec_type<double,4>(-0.000070,-0.000109,-0.000020,0),G2G::vec_type<double,4>(-0.000064,-0.000024,-0.000042,0),G2G::vec_type<double,4>(-0.000057,-0.000111,-0.000077,0),G2G::vec_type<double,4>(-0.000002,0.000337,0.000033,0),G2G::vec_type<double,4>(-0.000100,-0.000144,-0.000121,0),G2G::vec_type<double,4>(-0.000057,0.000094,-0.000062,0),G2G::vec_type<double,4>(-0.000065,-0.000183,-0.000088,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,-0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000004,0.000013,0.000007,0),G2G::vec_type<double,4>(0.000001,0.000011,-0.000001,0),G2G::vec_type<double,4>(-0.000000,-0.000009,0.000014,0)};
    G2G::vec_type<double,4> hess2[221] = {G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000001,0.000001,-0.000001,0),G2G::vec_type<double,4>(-0.000000,0.000001,-0.000000,0),G2G::vec_type<double,4>(-0.000001,0.000000,-0.000001,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000001,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000017,0.000027,-0.000011,0),G2G::vec_type<double,4>(0.000003,0.000011,0.000005,0),G2G::vec_type<double,4>(0.000010,0.000011,0.000009,0),G2G::vec_type<double,4>(0.000005,0.000000,0.000001,0),G2G::vec_type<double,4>(0.000003,0.000002,0.000007,0),G2G::vec_type<double,4>(-0.000028,0.000011,-0.000050,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000001,0.000010,0.000001,0),G2G::vec_type<double,4>(0.000002,0.000001,0.000002,0),G2G::vec_type<double,4>(-0.000008,0.000008,-0.000008,0),G2G::vec_type<double,4>(0.000003,0.000002,0.000006,0),G2G::vec_type<double,4>(-0.000005,0.000008,-0.000008,0),G2G::vec_type<double,4>(-0.000008,0.000005,-0.000008,0),G2G::vec_type<double,4>(0.000006,0.000001,0.000003,0),G2G::vec_type<double,4>(-0.000008,0.000008,-0.000004,0),G2G::vec_type<double,4>(0.000002,0.000002,0.000007,0),G2G::vec_type<double,4>(-0.000002,0.000006,-0.000006,0),G2G::vec_type<double,4>(-0.000006,0.000002,-0.000006,0),G2G::vec_type<double,4>(0.000007,0.000001,0.000002,0),G2G::vec_type<double,4>(-0.000005,0.000005,-0.000001,0),G2G::vec_type<double,4>(-0.000011,0.000005,-0.000005,0),G2G::vec_type<double,4>(0.000005,0.000005,0.000005,0),G2G::vec_type<double,4>(-0.000005,0.000011,-0.000005,0),G2G::vec_type<double,4>(-0.000005,0.000005,-0.000011,0),G2G::vec_type<double,4>(0.000002,0.000005,0.000001,0),G2G::vec_type<double,4>(0.000001,0.000006,0.000002,0),G2G::vec_type<double,4>(-0.000002,0.000010,-0.000001,0),G2G::vec_type<double,4>(0.000005,0.000007,0.000003,0),G2G::vec_type<double,4>(-0.000001,0.000010,-0.000002,0),G2G::vec_type<double,4>(0.000003,0.000008,0.000004,0),G2G::vec_type<double,4>(0.000011,0.000022,0.000012,0),G2G::vec_type<double,4>(-0.000008,0.000006,-0.000012,0),G2G::vec_type<double,4>(-0.000021,0.000022,-0.000020,0),G2G::vec_type<double,4>(0.000007,-0.000005,0.000015,0),G2G::vec_type<double,4>(-0.000010,0.000022,-0.000020,0),G2G::vec_type<double,4>(-0.000080,0.000147,-0.000094,0),G2G::vec_type<double,4>(-0.000022,0.000011,-0.000021,0),G2G::vec_type<double,4>(0.000013,-0.000005,0.000001,0),G2G::vec_type<double,4>(-0.000019,0.000020,-0.000008,0),G2G::vec_type<double,4>(0.000007,-0.000006,0.000026,0),G2G::vec_type<double,4>(-0.000000,0.000012,-0.000008,0),G2G::vec_type<double,4>(-0.000013,0.000002,-0.000012,0),G2G::vec_type<double,4>(0.000022,-0.000008,0.000003,0),G2G::vec_type<double,4>(-0.000006,0.000008,0.000002,0),G2G::vec_type<double,4>(-0.000056,0.000071,-0.000057,0),G2G::vec_type<double,4>(-0.000029,0.000011,-0.000009,0),G2G::vec_type<double,4>(0.000020,0.000001,0.000020,0),G2G::vec_type<double,4>(-0.000009,0.000028,-0.000008,0),G2G::vec_type<double,4>(-0.000036,0.000043,-0.000048,0),G2G::vec_type<double,4>(-0.000012,0.000012,-0.000029,0),G2G::vec_type<double,4>(0.000016,0.000004,0.000008,0),G2G::vec_type<double,4>(0.000007,0.000008,0.000015,0),G2G::vec_type<double,4>(0.000002,0.000021,0.000003,0),G2G::vec_type<double,4>(0.000022,0.000007,0.000014,0),G2G::vec_type<double,4>(0.000002,0.000023,0.000002,0),G2G::vec_type<double,4>(0.000014,0.000010,0.000022,0),G2G::vec_type<double,4>(0.000034,0.000015,0.000036,0),G2G::vec_type<double,4>(-0.000039,0.000016,-0.000054,0),G2G::vec_type<double,4>(-0.000021,0.000024,-0.000017,0),G2G::vec_type<double,4>(-0.000001,-0.000014,0.000013,0),G2G::vec_type<double,4>(-0.000003,0.000022,-0.000013,0),G2G::vec_type<double,4>(-0.000189,0.000199,-0.000226,0),G2G::vec_type<double,4>(-0.000022,0.000007,-0.000018,0),G2G::vec_type<double,4>(0.000009,-0.000009,-0.000019,0),G2G::vec_type<double,4>(-0.000014,0.000018,0.000003,0),G2G::vec_type<double,4>(0.000035,-0.000013,0.000032,0),G2G::vec_type<double,4>(0.000002,0.000031,0.000005,0),G2G::vec_type<double,4>(0.000045,-0.000013,0.000021,0),G2G::vec_type<double,4>(0.000021,-0.000005,0.000046,0),G2G::vec_type<double,4>(0.000022,0.000016,0.000021,0),G2G::vec_type<double,4>(0.000049,-0.000008,0.000029,0),G2G::vec_type<double,4>(0.000017,0.000021,0.000023,0),G2G::vec_type<double,4>(0.000032,-0.000003,0.000050,0),G2G::vec_type<double,4>(0.000060,0.000018,0.000061,0),G2G::vec_type<double,4>(-0.000067,0.000023,-0.000096,0),G2G::vec_type<double,4>(-0.000019,0.000026,-0.000011,0),G2G::vec_type<double,4>(-0.000014,-0.000012,0.000008,0),G2G::vec_type<double,4>(0.000008,0.000023,-0.000004,0),G2G::vec_type<double,4>(-0.000262,0.000177,-0.000321,0),G2G::vec_type<double,4>(-0.000021,0.000001,-0.000012,0),G2G::vec_type<double,4>(0.000009,-0.000006,-0.000047,0),G2G::vec_type<double,4>(-0.000007,0.000016,0.000017,0),G2G::vec_type<double,4>(0.000050,-0.000013,0.000041,0),G2G::vec_type<double,4>(0.000016,0.000038,0.000021,0),G2G::vec_type<double,4>(0.000046,0.000016,0.000040,0),G2G::vec_type<double,4>(0.000077,-0.000010,0.000040,0),G2G::vec_type<double,4>(0.000036,0.000023,0.000049,0),G2G::vec_type<double,4>(0.000048,-0.000006,0.000079,0),G2G::vec_type<double,4>(0.000085,0.000042,0.000083,0),G2G::vec_type<double,4>(-0.000070,0.000022,-0.000113,0),G2G::vec_type<double,4>(-0.000028,0.000039,-0.000017,0),G2G::vec_type<double,4>(0.000072,0.000003,0.000055,0),G2G::vec_type<double,4>(0.000023,0.000061,0.000029,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(0.000000,0.000000,0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000000,0.000000,-0.000000,0),G2G::vec_type<double,4>(-0.000011,0.000010,-0.000019,0),G2G::vec_type<double,4>(0.000004,0.000001,-0.000003,0),G2G::vec_type<double,4>(0.000006,0.000014,0.000009,0)};

    /////////////////////////////
    // CUDA ARRAYS
    //template<class T, bool compute_energy, bool compute_factor, bool lda>
    //void libxc_exchange_correlation_gpu (LibxcProxy<T, WIDTH>* libxcProxy,

    double* energy_gpu = NULL;
    cudaMalloc((void**)&energy_gpu, sizeof(double)*number_of_points);

    double* factor_gpu = NULL;
    cudaMalloc ((void**)&factor_gpu, sizeof(double)*number_of_points);

    double* accumulated_density_gpu = NULL;
    cudaMalloc ((void**)&accumulated_density_gpu, sizeof(double)*number_of_points);

    double* contracted_gradient_gpu = NULL;
    cudaMalloc ((void**)&contracted_gradient_gpu, sizeof(double)*number_of_points);

    G2G::vec_type<double,WIDTH>* dxyz_gpu = NULL;
    cudaMalloc((void**)&dxyz_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    G2G::vec_type<double,WIDTH>* dd1_gpu = NULL;
    cudaMalloc((void**)&dd1_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    G2G::vec_type<double,WIDTH>* dd2_gpu = NULL;
    cudaMalloc((void**)&dd2_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    //////////////////////////////
    // SET CUDA ARRAYS VALUES
    cudaMemset(energy_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(factor_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(accumulated_density_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(contracted_gradient_gpu, 0, sizeof(double)*number_of_points);

    cudaMemcpy(accumulated_density_gpu, &dens_cpu, sizeof(double)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(contracted_gradient_gpu, &contracted_gradient_cpu, sizeof(double)*number_of_points, cudaMemcpyHostToDevice);

    cudaMemcpy(dxyz_gpu, &grad, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd1_gpu, &hess1, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd2_gpu, &hess2, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);

    //////////////////////////////
    // CREATE THE PROXY
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    //////////////////////////////
    // MAKE THE CALLS
    libxc_exchange_correlation_gpu<double, true, true, false> (
	&libxcProxy,
	energy_gpu,
	factor_gpu,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu,
        dd1_gpu,
	dd2_gpu);


    /////////////////////////////
    // PRINT THE RESULTS
    double* energy_cpu = (double*)malloc(sizeof(double)*number_of_points);
    double* factor_cpu = (double*)malloc(sizeof(double)*number_of_points);

    memset(energy_cpu,0,sizeof(double)*number_of_points);
    memset(factor_cpu,0,sizeof(double)*number_of_points);

    cudaMemcpy(energy_cpu, energy_gpu, sizeof(double)*number_of_points, cudaMemcpyDeviceToHost);
    cudaMemcpy(factor_cpu, factor_gpu, sizeof(double)*number_of_points, cudaMemcpyDeviceToHost);

    print_accumulate_point_data (NULL, NULL, NULL, energy_cpu, factor_cpu, NULL, NULL, number_of_points);

    /////////////////////////////
    // FREE MEMORY

    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(accumulated_density_gpu);
    cudaFree(contracted_gradient_gpu);
    cudaFree(dxyz_gpu);
    cudaFree(dd1_gpu);
    cudaFree(dd2_gpu);

    free(energy_cpu);
    free(factor_cpu);
#endif
}

////////////////////////////////////////////////////////////////
// Exchange correlation for DOUBLES

void do_libxc_exchange_correlation_gpu (int number_of_points,
    double *dens_cpu,
    double *contracted_gradient_cpu,
    G2G::vec_type<double,4>* grad,
    G2G::vec_type<double,4>* hess1,
    G2G::vec_type<double,4>* hess2) {

    printf("do_libxc_exchange_correlation_gpu(%i)\n", number_of_points);

#if FULL_DOUBLE
    /////////////////////////////
    // CUDA ARRAYS
    //template<class T, bool compute_energy, bool compute_factor, bool lda>
    //void libxc_exchange_correlation_gpu (LibxcProxy<T, WIDTH>* libxcProxy,

    double* energy_gpu = NULL;
    cudaMalloc((void**)&energy_gpu, sizeof(double)*number_of_points);

    double* factor_gpu = NULL;
    cudaMalloc ((void**)&factor_gpu, sizeof(double)*number_of_points);

    double* accumulated_density_gpu = NULL;
    cudaMalloc ((void**)&accumulated_density_gpu, sizeof(double)*number_of_points);

    double* contracted_gradient_gpu = NULL;
    cudaMalloc ((void**)&contracted_gradient_gpu, sizeof(double)*number_of_points);

    G2G::vec_type<double,WIDTH>* dxyz_gpu = NULL;
    cudaMalloc((void**)&dxyz_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    G2G::vec_type<double,WIDTH>* dd1_gpu = NULL;
    cudaMalloc((void**)&dd1_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    G2G::vec_type<double,WIDTH>* dd2_gpu = NULL;
    cudaMalloc((void**)&dd2_gpu, sizeof(G2G::vec_type<double,4>)*number_of_points);

    //////////////////////////////
    // SET CUDA ARRAYS VALUES
    cudaMemset(energy_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(factor_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(accumulated_density_gpu, 0, sizeof(double)*number_of_points);
    cudaMemset(contracted_gradient_gpu, 0, sizeof(double)*number_of_points);

    cudaMemcpy(accumulated_density_gpu, dens_cpu, sizeof(double)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(contracted_gradient_gpu, contracted_gradient_cpu, sizeof(double)*number_of_points, cudaMemcpyHostToDevice);

    cudaMemcpy(dxyz_gpu, grad, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd1_gpu, hess1, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd2_gpu, hess2, sizeof(G2G::vec_type<double,4>)*number_of_points, cudaMemcpyHostToDevice);

    //////////////////////////////
    // CREATE THE PROXY
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<double,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    //////////////////////////////
    // MAKE THE CALLS
    libxc_exchange_correlation_gpu<double, true, true, false> (
	&libxcProxy,
	energy_gpu,
	factor_gpu,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu,
        dd1_gpu,
	dd2_gpu);

    /////////////////////////////
    // PRINT THE RESULTS
    double* energy_cpu = (double*)malloc(sizeof(double)*number_of_points);
    double* factor_cpu = (double*)malloc(sizeof(double)*number_of_points);

    memset(energy_cpu,0,sizeof(double)*number_of_points);
    memset(factor_cpu,0,sizeof(double)*number_of_points);

    cudaMemcpy(energy_cpu, energy_gpu, sizeof(double)*number_of_points, cudaMemcpyDeviceToHost);
    cudaMemcpy(factor_cpu, factor_gpu, sizeof(double)*number_of_points, cudaMemcpyDeviceToHost);

    print_accumulate_point_data (NULL, NULL, NULL, energy_cpu, factor_cpu, NULL, NULL, number_of_points);

    /////////////////////////////
    // FREE MEMORY
    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(accumulated_density_gpu);
    cudaFree(contracted_gradient_gpu);
    cudaFree(dxyz_gpu);
    cudaFree(dd1_gpu);
    cudaFree(dd2_gpu);

    free(energy_cpu);
    free(factor_cpu);
#endif
}

//////////////////////////////////////////////
// Accumulate test for doubles
void accumulate_data_for_libxc_test0010()
{
    printf("accumulate_data_for_libxc_test0010()\n");

    ////////////////////////////////
    // PARAMS SETUP

    int number_of_points[9] = {221,227,256,537,1796,4007,2910,2910,3492};
    double* dens_cpu[9] = {dens_221,dens_227,dens_256,dens_537,dens_1796,dens_4007,dens_2910_1,dens_2910_2,dens_3492};
    double* contracted_gradients_cpu[9] = {contracted_grad_221,contracted_grad_227,contracted_grad_256,contracted_grad_537,contracted_grad_1796,contracted_grad_4007,contracted_grad_2910_1,contracted_grad_2910_2,contracted_grad_3492};
    G2G::vec_type<double,4>* grads[9] = {grad_221,grad_227,grad_256,grad_537,grad_1796,grad_4007,grad_2910_1,grad_2910_2,grad_3492};
    G2G::vec_type<double,4>* hess1s[9] = {hess1_221,hess1_227,hess1_256,hess1_537,hess1_1796,hess1_4007,hess1_2910_1,hess1_2910_2,hess1_3492};
    G2G::vec_type<double,4>* hess2s[9] = {hess2_221,hess2_227,hess2_256,hess2_537,hess2_1796,hess2_4007,hess2_2910_1,hess2_2910_2,hess2_3492};

    for (int i=0; i<9; i++) {
        do_libxc_exchange_correlation_gpu (number_of_points[i], 
	    dens_cpu[i], 
	    contracted_gradients_cpu[i],
	    grads[i],
	    hess1s[i],
	    hess2s[i]);
    }
}

//////////////////////////////////////////////////////////////////
// Exchange correlation for FLOATS

void do_libxc_exchange_correlation_gpu_float (int number_of_points,
    float *dens_cpu,
    float *contracted_gradient_cpu,
    G2G::vec_type<float,4>* grad,
    G2G::vec_type<float,4>* hess1,
    G2G::vec_type<float,4>* hess2) {

    printf("do_libxc_exchange_correlation_gpu_float(%i)\n", number_of_points);

    /////////////////////////////
    // CUDA ARRAYS
    float* energy_gpu = NULL;
    cudaMalloc((void**)&energy_gpu, sizeof(float)*number_of_points);

    float* factor_gpu = NULL;
    cudaMalloc ((void**)&factor_gpu, sizeof(float)*number_of_points);

    float* accumulated_density_gpu = NULL;
    cudaMalloc ((void**)&accumulated_density_gpu, sizeof(float)*number_of_points);

    float* contracted_gradient_gpu = NULL;
    cudaMalloc ((void**)&contracted_gradient_gpu, sizeof(float)*number_of_points);

    G2G::vec_type<float,WIDTH>* dxyz_gpu = NULL;
    cudaMalloc((void**)&dxyz_gpu, sizeof(G2G::vec_type<float,4>)*number_of_points);

    G2G::vec_type<float,WIDTH>* dd1_gpu = NULL;
    cudaMalloc((void**)&dd1_gpu, sizeof(G2G::vec_type<float,4>)*number_of_points);

    G2G::vec_type<float,WIDTH>* dd2_gpu = NULL;
    cudaMalloc((void**)&dd2_gpu, sizeof(G2G::vec_type<float,4>)*number_of_points);

    //////////////////////////////
    // SET CUDA ARRAYS VALUES
    cudaMemset(energy_gpu, 0, sizeof(float)*number_of_points);
    cudaMemset(factor_gpu, 0, sizeof(float)*number_of_points);
    cudaMemset(accumulated_density_gpu, 0, sizeof(float)*number_of_points);
    cudaMemset(contracted_gradient_gpu, 0, sizeof(float)*number_of_points);

    cudaMemcpy(accumulated_density_gpu, dens_cpu, sizeof(float)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(contracted_gradient_gpu, contracted_gradient_cpu, sizeof(float)*number_of_points, cudaMemcpyHostToDevice);

    cudaMemcpy(dxyz_gpu, grad, sizeof(G2G::vec_type<float,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd1_gpu, hess1, sizeof(G2G::vec_type<float,4>)*number_of_points, cudaMemcpyHostToDevice);
    cudaMemcpy(dd2_gpu, hess2, sizeof(G2G::vec_type<float,4>)*number_of_points, cudaMemcpyHostToDevice);

    //////////////////////////////
    // CREATE THE PROXY
    const int nspin = 1;
    const int functionalExchange = 1101;
    const int functionalCorrelation = 1130;
    LibxcProxy<float,4> libxcProxy(functionalExchange, functionalCorrelation, nspin);

    //////////////////////////////
    // MAKE THE CALLS
/*
    libxc_exchange_correlation_gpu<float, true, true, false> (
	&libxcProxy,
	energy_gpu,
	factor_gpu,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu,
        dd1_gpu,
	dd2_gpu);
*/

    libxc_exchange_correlation_gpu<float, false, true, false> (
	&libxcProxy,
	NULL,
	factor_gpu,
	number_of_points,
	accumulated_density_gpu,
	dxyz_gpu,
        dd1_gpu,
	dd2_gpu);

    /////////////////////////////
    // PRINT THE RESULTS
    float* energy_cpu = (float*)malloc(sizeof(float)*number_of_points);
    float* factor_cpu = (float*)malloc(sizeof(float)*number_of_points);

    memset(energy_cpu,0,sizeof(float)*number_of_points);
    memset(factor_cpu,0,sizeof(float)*number_of_points);

    cudaMemcpy(energy_cpu, energy_gpu, sizeof(float)*number_of_points, cudaMemcpyDeviceToHost);
    cudaMemcpy(factor_cpu, factor_gpu, sizeof(float)*number_of_points, cudaMemcpyDeviceToHost);

    print_accumulate_point_data (NULL, NULL, NULL, energy_cpu, factor_cpu, NULL, NULL, number_of_points);

    /////////////////////////////
    // FREE MEMORY
    cudaFree(energy_gpu);
    cudaFree(factor_gpu);
    cudaFree(accumulated_density_gpu);
    cudaFree(contracted_gradient_gpu);
    cudaFree(dxyz_gpu);
    cudaFree(dd1_gpu);
    cudaFree(dd2_gpu);

    free(energy_cpu);
    free(factor_cpu);
}


////////////////////////////////////////////////
// Accumulate data test for floats
void accumulate_data_for_libxc_test0011()
{
    printf("accumulate_data_for_libxc_test0011()\n");

    ////////////////////////////////
    // PARAMS SETUP

    int number_of_points[9] = {221,227,256,537,1796,4007,2910,2910,3492};
    float* dens_cpu[9] = {dens_221_f,dens_227_f,dens_256_f,dens_537_f,dens_1796_f,dens_4007_f,dens_2910_1_f,dens_2910_2_f,dens_3492_f};
    float* contracted_gradients_cpu[9] = {contracted_grad_221_f,contracted_grad_227_f,contracted_grad_256_f,contracted_grad_537_f,contracted_grad_1796_f,contracted_grad_4007_f,contracted_grad_2910_1_f,contracted_grad_2910_2_f,contracted_grad_3492_f};
    G2G::vec_type<float,4>* grads[9] = {grad_221_f,grad_227_f,grad_256_f,grad_537_f,grad_1796_f,grad_4007_f,grad_2910_1_f,grad_2910_2_f,grad_3492_f};
    G2G::vec_type<float,4>* hess1s[9] = {hess1_221_f,hess1_227_f,hess1_256_f,hess1_537_f,hess1_1796_f,hess1_4007_f,hess1_2910_1_f,hess1_2910_2_f,hess1_3492_f};
    G2G::vec_type<float,4>* hess2s[9] = {hess2_221_f,hess2_227_f,hess2_256_f,hess2_537_f,hess2_1796_f,hess2_4007_f,hess2_2910_1_f,hess2_2910_2_f,hess2_3492_f};

    for (int i=0; i<9; i++) {
        do_libxc_exchange_correlation_gpu_float (number_of_points[i], 
	    dens_cpu[i], 
	    contracted_gradients_cpu[i],
	    grads[i],
	    hess1s[i],
	    hess2s[i]);
    }
}


/////////////////////////////////////
//// MAIN

int main(int argc, char **argv)
{
    printf("********************************\n");
    printf("** Accumulate Point GPU test  **\n");
    printf("********************************\n");

    //gpu_accumulate_point_test0001();
    //cpu_accumulate_point_test0001();
    //accumulate_data_for_libxc_test0001();
    //accumulate_data_for_libxc_test0002();
    //accumulate_data_for_libxc_test0003();
    //accumulate_data_for_libxc_test0004();
    //accumulate_data_for_libxc_test0005();
    //accumulate_data_for_libxc_test0006();
    //accumulate_data_for_libxc_test0007();
    //accumulate_data_for_libxc_test0008(100);
    //accumulate_data_for_libxc_test0009();
#if FULL_DOUBLE
    accumulate_data_for_libxc_test0010();
#else
    accumulate_data_for_libxc_test0011();
#endif

    printf("*************************\n");
    printf("**      Test End       **\n");
    printf("*************************\n");

    return 0;
}