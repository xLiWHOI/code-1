add_library(ncdf
            create_restart_ncdf.F90
            grid_ncdf.F90
            init_2d_ncdf.F90
            init_3d_ncdf.F90
            init_grid_ncdf.F90
#            init_mean_ncdf.F90
            ncdf_2d_bdy.F90
            ncdf_2d.F90
            ncdf_3d_bdy.F90
            ncdf_3d_bio_bdy.F90
            ncdf_3d.F90
            ncdf_close.F90
            ncdf_common.F90
            ncdf_get_field.F90
            get_2d_field_ncdf_by_id.F90
            ncdf_in.F90
#            ncdf_mean.F90
            ncdf_meteo.F90
            ncdf_restart.F90
            ncdf_rivers.F90
            ncdf_topo.F90
            open_restart_ncdf.F90
            read_restart_ncdf.F90
            save_2d_ncdf.F90
            save_3d_ncdf.F90
            save_grid_ncdf.F90
#            save_mean_ncdf.F90
            set_attributes.F90
            write_restart_ncdf.F90
           )
target_compile_definitions(ncdf PRIVATE REAL_4B=real\(4\))
target_link_libraries(ncdf PRIVATE domain 2d 3d output output_manager futils)
