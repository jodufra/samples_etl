
CREATE OR REPLACE PACKAGE PCK_TRANSFORM AS

   PROCEDURE main (p_duplicate_last_iteration BOOLEAN);

END PCK_TRANSFORM;
/
create or replace PACKAGE BODY PCK_TRANSFORM IS

   e_transformation EXCEPTION;

   -- *********************************************
   -- * PUTS AN ERROR IN THE FACT TABLE OF ERRORS *
   -- *********************************************
   PROCEDURE error_log(p_screen_name t_tel_screen.screen_name%TYPE,
                       p_hora_deteccao DATE,
                       p_source_key      t_tel_source.source_key%TYPE, 
                       p_iteration_key   t_tel_iteration.iteration_key%TYPE,
                       p_record_id       t_tel_error.record_id%TYPE,
                       p_severity        t_tel_error.error_severity%TYPE) IS
      v_date_key t_tel_date.date_key%TYPE;
      v_screen_key t_tel_screen.screen_key%TYPE;
   BEGIN
      -- obt�m o id da dimens�o �date� referente ao dia em que o erro foi detectado
      BEGIN
         SELECT date_key
         INTO v_date_key
         FROM t_tel_date
         WHERE TO_CHAR(date_full,'DD-MM-YYYY')=TO_CHAR(p_hora_deteccao,'DD-MM-YYYY');
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            pck_log.write_log('Error: could not find date key from "t_tel_date" ['||sqlerrm||']');
            RAISE e_transformation;
      END;

      BEGIN
         SELECT screen_key
         INTO v_screen_key
         FROM t_tel_screen
         WHERE UPPER(screen_name)=UPPER(p_screen_name);
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            pck_log.write_log('Error: could not find screen key from "t_tel_screen" ['||sqlerrm||']');
            RAISE e_transformation;
      END;

      -- Insere um facto
      INSERT INTO t_tel_error (date_key,screen_key,source_key,iteration_key, record_id, error_severity) VALUES (v_date_key,v_screen_key,p_source_key,p_iteration_key, p_record_id, p_severity);
   EXCEPTION
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not write quality problem to "t_tel_error" fact table ['||sqlerrm||']');
         RAISE e_transformation;
   END;



   -- *******************************************
   -- * DUPLICATE THE LAST SCHEDULED ITERATION  *
   -- *******************************************
   PROCEDURE duplicate_last_iteration(p_start_date t_tel_iteration.iteration_start_date%TYPE) IS
      v_last_iteration_key t_tel_iteration.iteration_key%TYPE;
      v_new_iteration_key t_tel_iteration.iteration_key%TYPE;
      
      CURSOR c_scheduled_screens(p_iteration_key t_tel_iteration.iteration_key%TYPE) IS
         SELECT es.screen_key as screen_key,screen_name,screen_order,screen_source_key
         FROM t_tel_schedule es, t_tel_screen
         WHERE iteration_key=p_iteration_key AND
               es.screen_key = t_tel_screen.screen_key;
   BEGIN
      pck_log.write_log('Action: duplicate last iteration ['||sqlerrm||']');
      
      -- FIND THE LAST ITERATIONS'S KEY
      BEGIN
         SELECT MAX(iteration_key)
         INTO v_last_iteration_key
         FROM t_tel_iteration;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            pck_log.write_log('Error: could not find iteration key ['||sqlerrm||']');
            RAISE e_transformation;
      END;

      INSERT INTO t_tel_iteration(iteration_start_date) VALUES (p_start_date) RETURNING iteration_key INTO v_new_iteration_key;
      FOR rec IN c_scheduled_screens(v_last_iteration_key) LOOP
         -- SCHEDULE A SCREEN
         INSERT INTO t_tel_schedule(screen_key,iteration_key,source_key,screen_order)
         VALUES (rec.screen_key,v_new_iteration_key,rec.screen_source_key,rec.screen_order);
      END LOOP;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Error: found no screens to reschedule');
         RAISE e_transformation;
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not duplicate last iteration ['||sqlerrm||']');
         RAISE e_transformation;
   END;

   -- ####################### TRANSFORMATION ROUTINES #######################
   
    -- TRANSFORM ESTUDANTES
   PROCEDURE transform_estudantes IS
   BEGIN
      pck_log.write_log('Action: transform ESTUDANTES'' data');

      INSERT INTO t_clean_estudantes (estudante_natural_key,CURSO_KEY)
      SELECT e.cd_aluno, e.cd_curso
      FROM t_data_estudantes e
      WHERE e.rejected_by_screen='0';

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform ESTUDANTES ['||sqlerrm||']');
         RAISE e_transformation;
   END;  

    -- TRANSFORM CURSOS
  PROCEDURE transform_cursos IS
   BEGIN
      pck_log.write_log('Action: transform cursos'' data');

    INSERT INTO t_clean_cursos(
          curso_natural_key,
          curso_oficial_key,
          curso_nome,
          curso_nome_abv,
          curso_regime,
          curso_grau,
          curso_activo,
          curso_bolonha,
          curso_instituicao_key,
          curso_instituicao_nome,
          curso_instituicao_nome_abv)
    SELECT 
          c.cd_curso,
          c.cd_oficial,
          c.nm_curso,
          c.nm_cur_abr,
          c.cd_regime,
          c.ds_grau,
          CASE c.cd_activo WHEN 'S' THEN 'SIM' ELSE 'NAO' END,
          CASE c.cd_bolonha WHEN 'S' THEN 'SIM' ELSE 'NAO' END,
          o.cd_instituic,
          o.ds_instituic,
          o.ds_inst_abr
    FROM 
          T_DATA_CURSOS c,
          t_data_unidades_organicas o
    WHERE 
        o.cd_instituic = c.CD_INSTITUIC;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform cursos ['||sqlerrm||']');
         RAISE e_transformation;
   END;

    -- TRANSFORM TIPOS INSCRICAO
   PROCEDURE transform_tipos_inscricao IS
   BEGIN
      pck_log.write_log('Action: transform tipos inscricao'' data');

      INSERT INTO t_clean_tipos_inscricao(tipo_insc_natural_key,tipo_insc_descricao)
      select DISTINCT(CD_TIPO_INSC), DS_TIPO_INSC
      from T_DATA_INSCRICOES
      order by 1;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform tipos inscricao ['||sqlerrm||']');
         RAISE e_transformation;
   END;

  -- TRANSFORM UNIDADES_CURRICULARES
   PROCEDURE transform_ucs IS
      CURSOR cursor_cu IS
          SELECT 
                cu.UC_NOME as UC_NOME, 
                REGEXP_REPLACE(nvl(cu.AREA_CIENTIFICA_SIGLA,''), '\s') as AREA_CIENTIFICA_SIGLA, 
                nvl(ac.NOME,'') as AREA_CIENTIFICA, 
                REGEXP_REPLACE(nvl(cu.DEPARTAMENTO_SIGLA,''), '\s') as DEPARTAMENTO_SIGLA
          FROM 
                T_DATA_CURSO_UCS_NEW cu LEFT JOIN 
                T_DATA_AREAS_CIENTIFICAS_NEW ac on 
                      REGEXP_REPLACE(cu.AREA_CIENTIFICA_SIGLA, '\s') = REGEXP_REPLACE(ac.SIGLA, '\s') 
          WHERE cu.UC_NOME <> 'Unidade Curricular';
      v_ano_semestre VARCHAR2(100);
      v_curso_nome VARCHAR2(100);
   BEGIN
      pck_log.write_log('Action: transform ucs'' data');
      
      INSERT INTO T_CLEAN_UNIDADES_CURRICULARES(
              uc_natural_key,
              plano_key,
              curso_key,
              ramo_key,
              uc_nome,
              uc_nome_abv,
              uc_duracao,
              uc_ramo,
              uc_plano,
              uc_plano_activo)
      SELECT 
              uc.CD_DISCIP,
              uc.CD_PLANO,
              uc.CD_CURSO,
              uc.CD_RAMO,
              uc.DS_DISCIP,
              uc.DS_ABREVIATURA,
              uc.CD_DURACAO,
              r.NM_RAMO,
              p.NM_PLANO,
              CASE p.CD_ACTIVO WHEN 'S' THEN 'SIM' ELSE 'NAO' END 
      FROM 
              T_DATA_UNIDADES_CURRICULARES uc, 
              T_DATA_PLANOS p, 
              T_DATA_RAMOS r,
              T_DATA_CURSOS cu
      WHERE
              uc.CD_PLANO = p.CD_PLANO and 
              uc.CD_RAMO = r.CD_RAMO and
              uc.CD_CURSO = cu.CD_CURSO and
              r.CD_PLANO = p.CD_PLANO and
              r.CD_CURSO = cu.CD_CURSO and 
              p.CD_CURSO = cu.CD_CURSO and
              uc.REJECTED_BY_SCREEN = 0
      ORDER BY 1;
      
      
      -- JOIN DATA FROM CURSOR
      FOR rec in cursor_cu LOOP
        IF(rec.AREA_CIENTIFICA_SIGLA is null and rec.UC_NOME not like '%Ano%') then
          v_curso_nome:=rec.UC_NOME;
          continue;
        END IF; 
        
        IF(rec.AREA_CIENTIFICA_SIGLA is null and rec.UC_NOME like '%Ano%') then
          v_ano_semestre:=rec.UC_NOME;
          continue;
        END IF;
        
        -- Update
        UPDATE T_CLEAN_UNIDADES_CURRICULARES
        SET 
            uc_area_cientifica = rec.AREA_CIENTIFICA, 
            uc_area_cientifica_abv = rec.AREA_CIENTIFICA_SIGLA, 
            uc_departamento_abv = rec.DEPARTAMENTO_SIGLA, 
            uc_plano_ano_semestre = v_ano_semestre
        WHERE 
            CURSO_KEY in (SELECT cur.CD_CURSO FROM T_DATA_CURSOS cur WHERE INSTR(REGEXP_REPLACE(v_curso_nome, '\s'),REGEXP_REPLACE(cur.NM_CURSO, '\s'))  > 0) and 
            UPPER(TRIM(REGEXP_REPLACE(rec.uc_nome, '\s'))) = UPPER(TRIM(REGEXP_REPLACE(uc_nome, '\s')));  
      END LOOP;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform ucs ['||sqlerrm||']');
         RAISE e_transformation;
   END;

    -- TRANSFORM AVALIACOES
   PROCEDURE transform_avaliacoes IS
   BEGIN
      pck_log.write_log('Action: transform AVALIACOES'' data');

      INSERT INTO t_clean_avaliacoes(
          cd_lectivo,
          cd_duracao,
          cd_aluno,
          cd_curso_aluno,
          cd_discip,
          cd_plano,
          cd_epoca_aval,
          ds_epoca_aval,
          nr_avalia)
      select 
          cd_lectivo,
          cd_duracao,
          cd_aluno,
          cd_curso_aluno,
          cd_discip,
          cd_plano,
          cd_epoca_aval,
          ds_epoca_aval,
          nvl(nr_avalia,-1)
      from T_DATA_AVALIACOES 
      where REJECTED_BY_SCREEN = 0;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform AVALIACOES ['||sqlerrm||']');
         RAISE e_transformation;
   END;

 -- TRANSFORM INSCRICOES
   PROCEDURE transform_inscricoes IS
   BEGIN
      pck_log.write_log('Action: transform INSCRICOES'' data');

      INSERT INTO T_CLEAN_INSCRICOES(
          cd_lectivo,
          cd_curso_aluno,
          cd_plano,
          cd_ramo,
          cd_discip,
          cd_aluno,
          dt_inscri,
          cd_tipo_insc,
          ds_tipo_insc,
          ects,
          cd_epoca_aval,
          ds_epoca_aval)
      select 
          cd_lectivo,
          cd_curso_aluno,
          cd_plano,
          cd_ramo,
          cd_discip,
          cd_aluno,
          dt_inscri,
          cd_tipo_insc,
          ds_tipo_insc,
          ects,
          cd_epoca_aval,
          ds_epoca_aval
      from T_DATA_INSCRICOES 
      where REJECTED_BY_SCREEN = 0;

      pck_log.write_log('Done!');
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         pck_log.write_log('Info: Found no lines to transform');
         pck_log.write_log('Done!');
      WHEN OTHERS THEN
         pck_log.write_log('Error: could not transform INSCRICOES ['||sqlerrm||']');
         RAISE e_transformation;
   END;

   -- *****************************************************************************************************
   -- *                                             MAIN                                                  *
   -- *                                                                                                   *
   -- * EXECUTE THE TRANSFORMATION PROCESS                                                               *
   -- * IN                                                                                                *
   -- *     p_duplicate_last_iteration: TRUE=duplicate last iteration and its schedule (FOR TESTS ONLY!) *
   -- *****************************************************************************************************
   PROCEDURE main (p_duplicate_last_iteration BOOLEAN) IS

      -- GET ALL SCHEDULED SCREENS
      cursor scheduled_screens_cursor(p_iteration_key t_tel_iteration.iteration_key%TYPE) IS
         SELECT UPPER(screen_name) screen_name,source_key,screen_order
         FROM t_tel_schedule, t_tel_screen
         WHERE iteration_key=p_iteration_key AND  t_tel_schedule.screen_key=t_tel_screen.screen_key;

      v_iteration_key t_tel_iteration.iteration_key%TYPE;
      v_sql  VARCHAR2(1000);
   BEGIN
      pck_log.write_log('Info: entering TRANSFORMATION stage');
      -- DUPLICATES THE LAST ITERATION WITH THEN CORRESPONDING SCHEDULE
      IF p_duplicate_last_iteration THEN
         duplicate_last_iteration(SYSDATE);
      END IF;

      -- CLEAN ALL _clean TABLES
      pck_log.write_log('Action: Delete old _clean tables *');
      DELETE FROM t_clean_avaliacoes;
      DELETE FROM t_clean_inscricoes;
      DELETE FROM t_clean_cursos;
      DELETE FROM t_clean_estudantes;
      DELETE FROM t_clean_unidades_curriculares;
     DELETE FROM  t_clean_tipos_inscricao;
      pck_log.write_log('Done!');

      -- FIND THE MOST RECENTLY SCHEDULED ITERATION
      BEGIN
         select ITERATION_KEY  into v_iteration_key from T_TEL_ITERATION
         where ITERATION_START_DATE = (select max(ITERATION_START_DATE) from  T_TEL_ITERATION group by ITERATION_KEY);
      EXCEPTION
         WHEN OTHERS THEN
            RAISE e_transformation;
      END;

      pck_log.write_log('Info: starting scheduled screens');

      -- RUN ALL SCHEDULED SCREENS
      FOR rec IN scheduled_screens_cursor(v_iteration_key) LOOP
         v_sql:= 'BEGIN PCK_TRANSFORM.' || rec.screen_name || '(:b1, :b2, :b3); END;';
         EXECUTE IMMEDIATE v_sql USING v_iteration_key, rec.source_key, rec.screen_order;
      END LOOP;

      pck_log.write_log('Info: all scheduled screens executed');
      
      -- EXECUTE THE TRANSFORMATION ROUTINES
      pck_log.write_log('Info: starting data transformation');
        transform_tipos_inscricao;
        transform_estudantes;
        transform_cursos;
        transform_ucs;
        transform_avaliacoes;
        transform_inscricoes; 
      
      pck_log.write_log('Info: data transformation completed');
      COMMIT;
      pck_log.write_log('Info: All transformed data commited to database');
      pck_log.write_log('Info: TRANSFORMATION stage completed');
   EXCEPTION
      WHEN e_transformation THEN
         pck_log.write_halt_transformation_msg;
         ROLLBACK;
      WHEN OTHERS THEN
         ROLLBACK;
         pck_log.write_log('Error: critical error ['||sqlerrm||']');
         pck_log.write_halt_transformation_msg;
   END;

end pck_transform;
/