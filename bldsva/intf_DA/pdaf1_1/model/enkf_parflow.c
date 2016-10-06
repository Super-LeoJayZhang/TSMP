/*-----------------------------------------------------------------------------------------
Copyright (c) 2013-2016 by Wolfgang Kurtz and Guowei He (Forschungszentrum Juelich GmbH)

This file is part of TerrSysMP-PDAF

TerrSysMP-PDAF is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

TerrSysMP-PDAF is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU LesserGeneral Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with TerrSysMP-PDAF.  If not, see <http://www.gnu.org/licenses/>.
-------------------------------------------------------------------------------------------*/


/*-----------------------------------------------------------------------------------------
enkf_parflow.c: Wrapper functions for ParFlow
-------------------------------------------------------------------------------------------*/
#include "enkf.h"
#include "parflow.h"
#include "solver.h"

#include "enkf_parflow.h"
#include <string.h>

amps_ThreadLocalDcl(PFModule *, Solver_module);
amps_ThreadLocalDcl(PFModule *, solver);
amps_ThreadLocalDcl(Vector *, evap_trans);
amps_ThreadLocalDcl(Vector *, vpress_dummy);
amps_ThreadLocalDcl(PFModule *, problem);

void init_idx_map_subvec2state(Vector *pf_vector) {
	Grid *grid = VectorGrid(pf_vector);
	int sg;
        double *tmpdat;

	// allocate x, y z coords
	xcoord = (double *) malloc(enkf_subvecsize * sizeof(double));
	ycoord = (double *) malloc(enkf_subvecsize * sizeof(double));
	//zcoord = (double *) malloc(enkf_subvecsize * sizeof(double));
	//tmpdat = (double *) malloc(enkf_subvecsize * sizeof(double));

	// copy dz_mult to double
	ProblemData * problem_data = GetProblemDataRichards(solver);
	Vector * dz_mult = ProblemDataZmult(problem_data);
	Problem * problem = GetProblemRichards(solver);
	//PFModule * dz_mult_module = ProblemdzScale(problem);
	//char * name;
	//name = "dzScale.nzListNumber";

	//int num_dz = GetDouble(name);
	//int ir;
	//double values[num_dz];
	//char key[IDB_MAX_KEY_LEN];
	//for (ir = 0; ir < num_dz; ir++) {
	//	sprintf(key, "Cell.%d.dzScale.Value", ir);
	//	values[ir] = GetDouble(key);
	//}
	//PF2ENKF(dz_mult, zcoord);

	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);

		int ix = SubgridIX(subgrid);
		int iy = SubgridIY(subgrid);
		int iz = SubgridIZ(subgrid);

		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);

		int nx_glob = BackgroundNX(GlobalsBackground);
		int ny_glob = BackgroundNY(GlobalsBackground);

		int i, j, k;
		int counter = 0;

		for (k = iz; k < iz + nz; k++) {
			for (j = iy; j < iy + ny; j++) {
				for (i = ix; i < ix + nx; i++) {
					idx_map_subvec2state[counter] = nx_glob * ny_glob * k	+ nx_glob * j + i;
					idx_map_subvec2state[counter] += 1; // wolfgang's fix for C -> Fortran index
					xcoord[counter] = i * SubgridDX(subgrid) + 0.5*SubgridDX(subgrid); //SubgridX(subgrid) ;//+ i * SubgridDX(subgrid);
					ycoord[counter] = j * SubgridDY(subgrid) + 0.5*SubgridDY(subgrid); //SubgridY(subgrid) ;//+ j * SubgridDY(subgrid);
					//zcoord[counter] = SubgridZ(subgrid) + k * SubgridDZ(subgrid)*values[k];
                                        //tmpdat[counter] = (double)idx_map_subvec2state[counter];
					counter++;
                                        
				}
			}
		}
    /* store local dimensions for later use */
    nx_local = nx;
    ny_local = ny;
    nz_local = nz;
    origin_local[0] = ix+1;
    origin_local[1] = iy+1;
    origin_local[2] = iz+1;
	}
    //enkf_printvec("info","index", tmpdat);
    //enkf_printvec("info","xcoord", xcoord);
    //enkf_printvec("info","ycoord", ycoord);
    //enkf_printvec("info","zcoord", zcoord);
    //free(tmpdat);
}

void PseudoAdvanceRichards(PFModule *this_module, double start_time, /* Starting time */
double stop_time, /* Stopping time */
PFModule *time_step_control, /* Use this module to control timestep if supplied */
Vector *evap_trans, /* Flux from land surface model */
Vector **pressure_out, /* Output vars */
Vector **porosity_out, Vector **saturation_out);
// gw end

void enkfparflowinit(int ac, char *av[], char *input_file) {

	Grid *grid;

	char *filename = input_file;
	MPI_Comm pfcomm;

#ifdef PARFLOW_STAND_ALONE        
	pfcomm = MPI_Comm_f2c(comm_model_pdaf);
#endif

	/*-----------------------------------------------------------------------
	 * Initialize AMPS from existing MPI state
	 *-----------------------------------------------------------------------*/
#ifdef COUP_OAS_PFL
	if (amps_Init(&ac, &av))
	{
#else
	// Parflow stand alone. No need to guard becasue CLM stand alone should not compile this file.
	if (amps_EmbeddedInit_tsmp(pfcomm))
	{
#endif
		amps_Printf("Error: amps_EmbeddedInit initalization failed\n");
		exit(1);
	}

	/*-----------------------------------------------------------------------
	 * Set up globals structure
	 *-----------------------------------------------------------------------*/
	NewGlobals(filename);

	/*-----------------------------------------------------------------------
	 * Read the Users Input Deck
	 *-----------------------------------------------------------------------*/
	amps_ThreadLocal(input_database) = IDB_NewDB(GlobalsInFileName);

	/*-----------------------------------------------------------------------
	 * Setup log printing
	 *-----------------------------------------------------------------------*/
	NewLogging();

	/*-----------------------------------------------------------------------
	 * Setup timing table
	 *-----------------------------------------------------------------------*/
	NewTiming();

	/* End of main includes */

	/* Begin of Solver includes */
	GlobalsNumProcsX = GetIntDefault("Process.Topology.P", 1);
	GlobalsNumProcsY = GetIntDefault("Process.Topology.Q", 1);
	GlobalsNumProcsZ = GetIntDefault("Process.Topology.R", 1);

	GlobalsNumProcs = amps_Size(amps_CommWorld);

	GlobalsBackground = ReadBackground();

	GlobalsUserGrid = ReadUserGrid();

	SetBackgroundBounds(GlobalsBackground, GlobalsUserGrid);

	GlobalsMaxRefLevel = 0;

	amps_ThreadLocal(Solver_module) = PFModuleNewModuleType(
			SolverImpesNewPublicXtraInvoke, SolverRichards, ("Solver"));

	amps_ThreadLocal(solver) = PFModuleNewInstance(
			amps_ThreadLocal(Solver_module), ());
	/* End of solver includes */

	SetupRichards(amps_ThreadLocal(solver));

	/* Create the flow grid */
	grid = CreateGrid(GlobalsUserGrid);

	/* Create the PF vector holding flux */
	amps_ThreadLocal(evap_trans) = NewVectorType(grid, 1, 1,
			vector_cell_centered);
	InitVectorAll(amps_ThreadLocal(evap_trans), 0.0);

	/* kuw: create pf vector for printing results to pfb files */
	amps_ThreadLocal(vpress_dummy) = NewVectorType(grid, 1, 1,
			vector_cell_centered);
	InitVectorAll(amps_ThreadLocal(vpress_dummy), 0.0);
	enkf_subvecsize = enkf_getsubvectorsize(grid);
  
        if(pf_olfmasking == 2){
          FILE *friverid=NULL;
          int i;
          friverid = fopen("river.dat","rb");
          fscanf(friverid,"%d",&nriverid);
          riveridx = (int*) calloc(sizeof(int),nriverid);
          riveridy = (int*) calloc(sizeof(int),nriverid);
          for(i=0;i<nriverid;i++){
            fscanf(friverid,"%d %d",&riveridx[i],&riveridy[i]);
            riveridx[i] = riveridx[i]-1;
            riveridy[i] = riveridy[i]-1;
          }
          fclose(friverid);
        }

}

void parflow_oasis_init(double current_time, double dt) {
	double stop_time = current_time + dt;

	Vector *pressure_out;
	Vector *porosity_out;
	Vector *saturation_out;

	VectorUpdateCommHandle *handle;

	handle = InitVectorUpdate(evap_trans, VectorUpdateAll);
	FinalizeVectorUpdate(handle);

	PFModule *time_step_control;

	time_step_control = NewPFModule((void *) SelectTimeStep,
			(void *) SelectTimeStepInitInstanceXtra,
			(void *) SelectTimeStepFreeInstanceXtra,
			(void *) SelectTimeStepNewPublicXtra,
			(void *) SelectTimeStepFreePublicXtra,
			(void *) SelectTimeStepSizeOfTempData, NULL, NULL);

	ThisPFModule = time_step_control;
	SelectTimeStepNewPublicXtra();
	ThisPFModule = NULL;

	PFModule *time_step_control_instance = PFModuleNewInstance(
			time_step_control, ());

	// gw init the OAS, but weird implicit declaration..
	PseudoAdvanceRichards(amps_ThreadLocal(solver), current_time, stop_time,
			time_step_control_instance, amps_ThreadLocal(evap_trans),
			&pressure_out, &porosity_out, &saturation_out);

	PFModuleFreeInstance(time_step_control_instance);
	PFModuleFreeModule(time_step_control);

	// gw: init idx as well
        Problem *problem = GetProblemRichards(solver);
        Vector *pressure_in = GetPressureRichards(solver);
	init_idx_map_subvec2state(pressure_in);
}

void enkfparflowadvance(double current_time, double dt)

{
	double stop_time = current_time + dt;
	int i,j;

	Vector *pressure_out;
	Vector *porosity_out;
	Vector *saturation_out;

	VectorUpdateCommHandle *handle;

	handle = InitVectorUpdate(evap_trans, VectorUpdateAll);
	FinalizeVectorUpdate(handle);

	AdvanceRichards(amps_ThreadLocal(solver), current_time, stop_time, NULL, amps_ThreadLocal(evap_trans), &pressure_out, &porosity_out, &saturation_out);

	handle = InitVectorUpdate(pressure_out, VectorUpdateAll);
	FinalizeVectorUpdate(handle);
	handle = InitVectorUpdate(porosity_out, VectorUpdateAll);
	FinalizeVectorUpdate(handle);
	handle = InitVectorUpdate(saturation_out, VectorUpdateAll);
	FinalizeVectorUpdate(handle);

	/* create state vector: pressure */
	if(pf_updateflag == 1) {
  	  PF2ENKF(pressure_out, subvec_p);
  	  for(i=0;i<enkf_subvecsize;i++) pf_statevec[i] = subvec_p[i];

          /* masking option using saturated cells only */
          if(pf_gwmasking == 1){
            for(i=0;i<enkf_subvecsize;i++){
              subvec_gwind[i] = 1.0;
              if(subvec_p[i]< 0.0) subvec_gwind[i] = 0.0;
            }
          }

          /* masking option using mixed state vector */
          if(pf_gwmasking == 2){
            int no_obs,haveobs,tmpidx; 
            MPI_Comm comm_couple_c = MPI_Comm_f2c(comm_couple);
            PF2ENKF(saturation_out, subvec_sat);
  	    PF2ENKF(porosity_out, subvec_porosity);
            MPI_Allreduce(subvec_sat,subvec_mean,enkf_subvecsize,MPI_DOUBLE,MPI_SUM,comm_couple_c);
            for(i=0;i<enkf_subvecsize;i++){
              subvec_gwind[i] = 1.0;
              if(subvec_mean[i]< (double)nreal){
                subvec_gwind[i] = 0.0;
                pf_statevec[i] = subvec_sat[i] * subvec_porosity[i]; 
              } 
            }
            if(task_id == 1 && pf_printgwmask == 1) enkf_printstatistics_pfb(subvec_gwind,"gwind",(int) (t_start/da_interval + stat_dumpoffset),outdir);
            get_obsindex_currentobsfile(&no_obs);
 
            for(i=0;i<no_obs;i++){
              haveobs=0;
              if((xidx_obs[i]>=origin_local[0]) && (xidx_obs[i]<(origin_local[0]+nx_local))){
                if((yidx_obs[i]>=origin_local[1]) && (yidx_obs[i]<(origin_local[1]+ny_local))){
                  if((zidx_obs[i]>=origin_local[2]) && (zidx_obs[i]<(origin_local[2]+nz_local))){
                    haveobs=1;
                  }
                }
              }
              if(haveobs && ind_obs[i]==1){
                for(j=0;j<=(zidx_obs[i]-origin_local[2]);j++){
                  tmpidx = nx_local*ny_local*j + nx_local*(yidx_obs[i]-origin_local[1]) + (xidx_obs[i]-origin_local[0]);
                  subvec_gwind[tmpidx] = 1.0;
                  pf_statevec[tmpidx] = subvec_p[tmpidx]; 
                }
              }
            }
            if(task_id == 1 && pf_printgwmask == 1) enkf_printstatistics_pfb(subvec_gwind,"gwind_corrected",(int) (t_start/da_interval + stat_dumpoffset),outdir);
            clean_obs_pf();
          }
        }

	/* create state vector: swc */
	if(pf_updateflag == 2){
	  PF2ENKF(saturation_out, subvec_sat);
	  PF2ENKF(porosity_out, subvec_porosity);
	  for(i=0;i<enkf_subvecsize;i++) pf_statevec[i] = subvec_sat[i] * subvec_porosity[i];
	}

	/* create state vector: joint swc + pressure */
        if(pf_updateflag == 3){
          PF2ENKF(pressure_out, subvec_p);
          PF2ENKF(saturation_out, subvec_sat);
          PF2ENKF(porosity_out, subvec_porosity);
	  for(i=0;i<enkf_subvecsize;i++) pf_statevec[i] = subvec_sat[i] * subvec_porosity[i];
          for(i=enkf_subvecsize,j=0;i<(2*enkf_subvecsize);i++,j++) pf_statevec[i] = subvec_p[j];
        }
       
	/* append hydraulic conductivity to state vector */
        if(pf_paramupdate == 1){
           ProblemData *problem_data = GetProblemDataRichards(solver);
           Vector      *perm_xx = ProblemDataPermeabilityX(problem_data);
           handle = InitVectorUpdate(perm_xx, VectorUpdateAll);
           FinalizeVectorUpdate(handle);
           PF2ENKF(perm_xx,subvec_param);
           for(i=(pf_statevecsize-enkf_subvecsize),j=0;i<pf_statevecsize;i++,j++) pf_statevec[i] = log10(subvec_param[j]);
        }

	/* append Mannings coefficient to state vector */
        if(pf_paramupdate == 2){
           ProblemData *problem_data = GetProblemDataRichards(solver);
           Vector       *mannings    = ProblemDataMannings(problem_data);
           handle = InitVectorUpdate(mannings, VectorUpdateAll);
           FinalizeVectorUpdate(handle);
           PF2ENKF(mannings,subvec_param);
           for(i=(pf_statevecsize-pf_paramvecsize),j=0;i<pf_statevecsize;i++,j++) pf_statevec[i] = log10(subvec_param[j]);
        }
}

void enkfparflowfinalize() {

	// gw: free assimilation data structures
	free(idx_map_subvec2state);
	free(xcoord);
	free(ycoord);
	free(zcoord);

	fflush(NULL);
	LogGlobals();
	PrintTiming();
	FreeLogging();
	FreeTiming();
	FreeGlobals();
	amps_Finalize();
}

int enkf_getsubvectorsize(Grid *grid) {
	int sg;
	int out = 0;
	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);
		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);
		out += nx * ny * nz; // kuw: correct?
	}
	return (out);
}

void PF2ENKF(Vector *pf_vector, double *enkf_subvec) {

	Grid *grid = VectorGrid(pf_vector);
	int sg;

	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);

		int ix = SubgridIX(subgrid);
		int iy = SubgridIY(subgrid);
		int iz = SubgridIZ(subgrid);

		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);


		Subvector *subvector = VectorSubvector(pf_vector, sg);
		double *subvector_data = SubvectorData(subvector);

		int i, j, k;
		int counter = 0;

		for (k = iz; k < iz + nz; k++) {
			for (j = iy; j < iy + ny; j++) {
				for (i = ix; i < ix + nx; i++) {
					int pf_index = SubvectorEltIndex(subvector, i, j, k);
					enkf_subvec[counter] = (subvector_data[pf_index]);
					counter++;
				}
			}
		}
	}
}

void ENKF2PF(Vector *pf_vector, double *enkf_subvec) {

	Grid *grid = VectorGrid(pf_vector);
	int sg;

	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);

		int ix = SubgridIX(subgrid);
		int iy = SubgridIY(subgrid);
		int iz = SubgridIZ(subgrid);

		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);

		Subvector *subvector = VectorSubvector(pf_vector, sg);
		double *subvector_data = SubvectorData(subvector);

		int i, j, k;
		int counter = 0;

		for (k = iz; k < iz + nz; k++) {
			for (j = iy; j < iy + ny; j++) {
				for (i = ix; i < ix + nx; i++) {
					int pf_index = SubvectorEltIndex(subvector, i, j, k);
					(subvector_data[pf_index]) = enkf_subvec[counter];
					counter++;
				}
			}
		}
	}
}

void ENKF2PF_masked(Vector *pf_vector, double *enkf_subvec, double *mask) {

	Grid *grid = VectorGrid(pf_vector);
	int sg;

	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);

		int ix = SubgridIX(subgrid);
		int iy = SubgridIY(subgrid);
		int iz = SubgridIZ(subgrid);

		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);

		Subvector *subvector = VectorSubvector(pf_vector, sg);
		double *subvector_data = SubvectorData(subvector);

		int i, j, k;
		int counter = 0;

		for (k = iz; k < iz + nz; k++) {
			for (j = iy; j < iy + ny; j++) {
				for (i = ix; i < ix + nx; i++) {
					int pf_index = SubvectorEltIndex(subvector, i, j, k);
					subvector_data[pf_index] = mask[counter]*enkf_subvec[counter] + (1.0-mask[counter])*subvector_data[pf_index];
					counter++;
				}
			}
		}
	}
}

void enkf_printvec(char *pre, char *suff, double *data) {
	Grid *grid = VectorGrid(vpress_dummy);
	int sg;

	ForSubgridI(sg, GridSubgrids(grid))
	{
		Subgrid *subgrid = GridSubgrid(grid, sg);
		int ix = SubgridIX(subgrid);
		int iy = SubgridIY(subgrid);
		int iz = SubgridIZ(subgrid);

		int nx = SubgridNX(subgrid);
		int ny = SubgridNY(subgrid);
		int nz = SubgridNZ(subgrid);
		Subvector *subvector = VectorSubvector(vpress_dummy, sg);
		double *subvector_data = SubvectorData(subvector);
		int i, j, k;
		int counter = 0;

		for (k = iz; k < iz + nz; k++) {
			for (j = iy; j < iy + ny; j++) {
				for (i = ix; i < ix + nx; i++) {
					int pf_index = SubvectorEltIndex(subvector, i, j, k);
					subvector_data[pf_index] = data[counter];
					counter++;
				}
			}
		}

	}

	WritePFBinary(pre, suff, vpress_dummy);
}

void enkf_printmannings(char *pre, char *suff){
    ProblemData *problem_data = GetProblemDataRichards(solver);
    WritePFBinary(pre,suff, ProblemDataMannings(problem_data));      
}


void update_parflow () {
  int i,j;
  VectorUpdateCommHandle *handle;

  if(pf_olfmasking == 1) mask_overlandcells();
  if(pf_olfmasking == 2) mask_overlandcells_river();
  
  if(pf_updateflag == 1) {
    Vector *pressure_in = GetPressureRichards(solver);

    /* no groundwater masking */
    if(pf_gwmasking == 0){
      ENKF2PF(pressure_in, pf_statevec);
    }

    /* groundwater masking using saturated cells only */
    if(pf_gwmasking == 1){
      ENKF2PF_masked(pressure_in, pf_statevec,subvec_gwind);
    }

    /* groundwater masking using mixed state vector */
    if(pf_gwmasking == 2){
      Problem      *problem = GetProblemRichards(solver);
      ProblemData  *problem_data = GetProblemDataRichards(solver);
      PFModule     *problem_saturation = ProblemSaturation(problem);
      double       gravity  = ProblemGravity(problem);
      Vector *saturation_in = GetSaturationRichards(solver);
      Vector *density       = GetDensityRichards(solver);
      int saturation_to_pressure_type = 1;

      /* first update swc cells from mixed state vector pf_statevec */
      for(i=0;i<enkf_subvecsize;i++){
        subvec_sat[i] = subvec_gwind[i]*subvec_sat[i] + (1.0-subvec_gwind[i])*pf_statevec[i]/subvec_porosity[i];
      }
      ENKF2PF(saturation_in,subvec_sat);
      global_ptr_this_pf_module = problem_saturation;
      SaturationToPressure(saturation_in,	pressure_in, density, gravity,problem_data, CALCFCN, saturation_to_pressure_type);
      global_ptr_this_pf_module = solver;
  
      /* second update remaining pressures cells from mixed state vector pf_statevec */
      ENKF2PF_masked(pressure_in,pf_statevec,subvec_gwind);
    }

    /* update ghost cells for pressure */
    handle = InitVectorUpdate(pressure_in, VectorUpdateAll);
    FinalizeVectorUpdate(handle);

  }
  
  if(pf_updateflag == 2){
    /* write state vector to saturation in parflow */
    Vector * saturation_in = GetSaturationRichards(solver);
    for(i=0;i<enkf_subvecsize;i++){
      pf_statevec[i] = pf_statevec[i] / subvec_porosity[i];
    }
    int saturation_to_pressure_type = 1;
    ENKF2PF(saturation_in, pf_statevec);
    Problem * problem = GetProblemRichards(solver);
    double gravity = ProblemGravity(problem);
    Vector * pressure_in = GetPressureRichards(solver);
    Vector * density = GetDensityRichards(solver);
    ProblemData * problem_data = GetProblemDataRichards(solver);
    PFModule * problem_saturation = ProblemSaturation(problem);
    // convert saturation to pressure
    global_ptr_this_pf_module = problem_saturation;
    SaturationToPressure(saturation_in,	pressure_in, density, gravity, problem_data, CALCFCN, saturation_to_pressure_type);
    global_ptr_this_pf_module = solver;
  
    PF2ENKF(pressure_in,subvec_p);
    handle = InitVectorUpdate(pressure_in, VectorUpdateAll);
    FinalizeVectorUpdate(handle);
  }
 
  if(pf_updateflag == 3){
    Vector *pressure_in = GetPressureRichards(solver);

    ENKF2PF(pressure_in,&pf_statevec[enkf_subvecsize]);

    handle = InitVectorUpdate(pressure_in, VectorUpdateAll);
    FinalizeVectorUpdate(handle);

  }

  if(pf_paramupdate == 1){
    ProblemData * problem_data = GetProblemDataRichards(solver);
    Vector            *perm_xx = ProblemDataPermeabilityX(problem_data);
    Vector            *perm_yy = ProblemDataPermeabilityY(problem_data);
    Vector            *perm_zz = ProblemDataPermeabilityZ(problem_data);
    int nshift = 0;
    if(pf_updateflag == 3){
      nshift = 2*enkf_subvecsize;
    }else{
      nshift = enkf_subvecsize;
    }
 
    /* update perm_xx */    
    for(i=nshift,j=0;i<(nshift+enkf_subvecsize);i++,j++) 
      subvec_param[j] = pf_statevec[i];

    ENKF2PF(perm_xx,subvec_param);
    handle = InitVectorUpdate(perm_xx, VectorUpdateAll);
    FinalizeVectorUpdate(handle);
 
    /* update perm_yy */
    for(i=nshift,j=0;i<(nshift+enkf_subvecsize);i++,j++) 
      subvec_param[j] = pf_statevec[i] * pf_aniso_perm_y;

    ENKF2PF(perm_yy,subvec_param);
    handle = InitVectorUpdate(perm_yy, VectorUpdateAll);
    FinalizeVectorUpdate(handle);
 
    /* update perm_zz */
    for(i=nshift,j=0;i<(nshift+enkf_subvecsize);i++,j++) 
      subvec_param[j] = pf_statevec[i] * pf_aniso_perm_z;

    ENKF2PF(perm_zz,subvec_param);
    handle = InitVectorUpdate(perm_zz, VectorUpdateAll);
    FinalizeVectorUpdate(handle);
 
  }

  if(pf_paramupdate == 2){
    ProblemData *problem_data = GetProblemDataRichards(solver);
    Vector       *mannings    = ProblemDataMannings(problem_data);
    int nshift = 0;
    if(pf_updateflag == 3){
      nshift = 2*enkf_subvecsize;
    }else{
      nshift = enkf_subvecsize;
    }
    /* update mannings */    
    for(i=nshift,j=0;i<(nshift+pf_paramvecsize);i++,j++) 
      subvec_param[j] = pf_statevec[i];

    ENKF2PF(mannings,subvec_param);
    handle = InitVectorUpdate(mannings, VectorUpdateAll);
    FinalizeVectorUpdate(handle);
  }
}

void mask_overlandcells()
{
  int i,j,k;
  int counter = 0;
  
  /* fast-forward counter to uppermost model layer */
  counter = nx_local*ny_local*(nz_local-1);

  /* mask updated values in uppermost model layer */
  if(pf_updateflag == 1){
    for(i=0;i<ny_local;i++){
      for(j=0;j<nx_local;j++){
        //if(subvec_p[counter]>0.0) pf_statevec[counter] = subvec_p[counter];
        pf_statevec[counter] = subvec_p[counter];
        counter++;
      }
    }
  }
  if(pf_updateflag == 2){
    for(i=0;i<ny_local;i++){
      for(j=0;j<nx_local;j++){
        //if(subvec_p[counter]>0.0) pf_statevec[counter] = subvec_sat[counter]*subvec_porosity[counter];
        pf_statevec[counter] = subvec_sat[counter]*subvec_porosity[counter];
        counter++;
      }
    }
  }
  if(pf_updateflag == 3){
    for(i=0;i<ny_local;i++){
      for(j=0;j<nx_local;j++){
        //if(subvec_p[counter]>0.0) pf_statevec[counter+enkf_subvecsize] = subvec_p[counter];
        pf_statevec[counter+enkf_subvecsize] = subvec_p[counter];
        counter++;
      }
    }
  }

}

void mask_overlandcells_river()
{
  int i,j,idx;

  Grid *grid = VectorGrid(vpress_dummy);
  int sg;
  
  ForSubgridI(sg, GridSubgrids(grid))
  {
    Subgrid *subgrid = GridSubgrid(grid, sg);
    
    int ix = SubgridIX(subgrid);
    int iy = SubgridIY(subgrid);
    int iz = SubgridIZ(subgrid);
    
    int nx = SubgridNX(subgrid);
    int ny = SubgridNY(subgrid);
    int nz = SubgridNZ(subgrid);

    for(i=0;i<nriverid;i++){
      if(riveridx[i]>=ix && riveridx[i]<(ix+nx) && riveridy[i]>=iy && riveridy[i]<(iy+ny)){
        for(j=iz;j<(iz+nz);j++){
          idx = nx*ny*j + (riveridy[i]-iy)*nx + (riveridx[i]-ix);
          if(pf_updateflag == 1) pf_statevec[idx] = subvec_p[idx];
          if(pf_updateflag == 2) pf_statevec[idx] = subvec_sat[idx]*subvec_porosity[idx];
          if(pf_updateflag == 3) pf_statevec[idx+enkf_subvecsize] = subvec_p[idx];
        }
      }
    }
  }
}


