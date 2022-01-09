--
-- PostgreSQL database dump
--

-- Dumped from database version 13.5 (Ubuntu 13.5-2.pgdg20.04+1)
-- Dumped by pg_dump version 13.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: udf_constructor_stand_yearly(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.udf_constructor_stand_yearly(year integer) RETURNS TABLE(constructor_id smallint, constructor_ref character varying, constructors_name character varying, team_nationality character varying, total_point smallint, total_win smallint, rank smallint)
    LANGUAGE sql
    AS $_$
SELECT *, ROW_NUMBER() OVER(ORDER BY total_points DESC) AS rank
FROM (
	select 
		constructor_id as cid
		, max(constructor_ref) as name_ref
		, max(constructors_name) as team_name
		, max(team_nationality) as team_country
		, sum(point) as total_points
		, sum(iswin) as total_win
	from vw_race_results 
	where year = cast($1 as char(4))
	group by constructor_id
) t;
$_$;


--
-- Name: udf_driver_stand_yearly(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.udf_driver_stand_yearly(year integer) RETURNS TABLE(driver_id smallint, driver_ref character varying, driver_fullname character varying, driver_code character, driver_number smallint, driver_nationality character varying, total_points smallint, win_total smallint, running_total_points smallint, gp_name character varying, rank smallint, team character varying, race_date date)
    LANGUAGE sql
    AS $_$
SELECT 
		driver_id
		,driver_ref
		,driver_fullname
		,driver_code
		,driver_number
		,driver_nationality
		,total_points
		,win_total
		,running_total_points
		,gp_name
		, dense_rank() OVER(order BY total_points desc) as rank
		, team 
		, date
	FROM (
		select gp_name
			, driver_id
			, driver_ref
			, driver_fullname	
			, driver_code		
			, driver_number		
			, driver_nationality
			, date
			, point
			, sum(point) over(partition by driver_id order by date ) as running_total_points
			, sum(point) over(partition by driver_id) as total_points
			, sum(iswin) over(partition by driver_id) as win_total
			, constructors_name as team
		from vw_race_results 
		where year = cast($1 as char(4))
	) T 
	ORDER BY total_points desc, date
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: fact_circuits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_circuits (
    circuit_id integer NOT NULL,
    circuit_ref character varying(50),
    circuit_name character varying(50),
    circuit_location character varying(30),
    country character varying(30),
    lat real,
    lng real,
    alt real,
    url character varying(200)
);


--
-- Name: fact_constructors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_constructors (
    constructor_id smallint NOT NULL,
    constructor_ref character varying(30),
    constructors_name character varying(30),
    nationality character varying(30),
    url character varying(150),
    color_code_hex character varying(30),
    color_code_rgb character varying(30)
);


--
-- Name: fact_drivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_drivers (
    driver_id smallint NOT NULL,
    driver_ref character varying(20),
    driver_number smallint,
    name_tag character(3),
    firstname character varying(30),
    lastname character varying(30),
    dob date,
    nationality character varying(20),
    url character varying(150)
);


--
-- Name: fact_race_gp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_race_gp (
    race_id smallint NOT NULL,
    year character(4),
    round smallint,
    circuit_id smallint,
    gp_name character varying(30),
    date date,
    "time" time without time zone,
    url character varying(150)
);


--
-- Name: fact_session_race_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_session_race_results (
    result_id integer NOT NULL,
    race_id integer,
    driver_id smallint,
    constructor_id smallint,
    number smallint,
    grid smallint,
    "position" smallint,
    position_str character varying(10),
    position_order smallint,
    laps smallint,
    "time" character varying(30),
    milliseconds bigint,
    fastest_lap smallint,
    rank smallint,
    fastest_lap_time time without time zone,
    status_id smallint
);


--
-- Name: lookup_status_gp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lookup_status_gp (
    status_id smallint NOT NULL,
    status_desc character varying(50) NOT NULL
);


--
-- Name: pointsmark; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pointsmark (
    pid integer NOT NULL,
    points integer NOT NULL
);


--
-- Name: vw_race_results; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_race_results AS
 SELECT fc.constructor_id,
    fc.constructors_name,
    fc.constructor_ref,
    fc.nationality AS team_nationality,
    fd.driver_id,
    fd.driver_ref,
    concat(fd.firstname, ' ', fd.lastname) AS driver_fullname,
    fd.nationality AS driver_nationality,
    frg.year,
    fsrs.number AS driver_number,
    fd.name_tag AS driver_code,
    COALESCE(pm.points, 0) AS point,
    fsrs.status_id,
    frg.gp_name,
    frg.date,
    fsrs.laps,
    sum(fsrs.laps) OVER (PARTITION BY fsrs.driver_id, frg.year) AS total_laps_year,
    fsrs."position",
        CASE
            WHEN (COALESCE(pm.points, 0) >= 19) THEN 1
            ELSE 0
        END AS iswin,
        CASE
            WHEN (COALESCE(pm.points, 0) = 18) THEN 1
            ELSE 0
        END AS is_second,
        CASE
            WHEN (COALESCE(pm.points, 0) = 15) THEN 1
            ELSE 0
        END AS is_third,
    sum(COALESCE(pm.points, 0)) OVER (PARTITION BY fsrs.driver_id ORDER BY frg.date) AS total_point_driver
   FROM ((((public.fact_session_race_results fsrs
     LEFT JOIN public.fact_race_gp frg ON ((fsrs.race_id = frg.race_id)))
     LEFT JOIN public.fact_drivers fd ON ((fsrs.driver_id = fd.driver_id)))
     LEFT JOIN public.fact_constructors fc ON ((fsrs.constructor_id = fc.constructor_id)))
     LEFT JOIN public.pointsmark pm ON ((fsrs.position_order = pm.pid)));


--
-- Data for Name: fact_circuits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_circuits (circuit_id, circuit_ref, circuit_name, circuit_location, country, lat, lng, alt, url) FROM stdin;
1	albert_park	Albert Park Grand Prix Circuit	Melbourne	Australia	-37.8497	144.968	10	http://en.wikipedia.org/wiki/Melbourne_Grand_Prix_Circuit
2	sepang	Sepang International Circuit	Kuala Lumpur	Malaysia	2.76083	101.738	18	http://en.wikipedia.org/wiki/Sepang_International_Circuit
3	bahrain	Bahrain International Circuit	Sakhir	Bahrain	26.0325	50.5106	7	http://en.wikipedia.org/wiki/Bahrain_International_Circuit
4	catalunya	Circuit de Barcelona-Catalunya	Montmeló	Spain	41.57	2.26111	109	http://en.wikipedia.org/wiki/Circuit_de_Barcelona-Catalunya
5	istanbul	Istanbul Park	Istanbul	Turkey	40.9517	29.405	130	http://en.wikipedia.org/wiki/Istanbul_Park
6	monaco	Circuit de Monaco	Monte-Carlo	Monaco	43.7347	7.42056	7	http://en.wikipedia.org/wiki/Circuit_de_Monaco
7	villeneuve	Circuit Gilles Villeneuve	Montreal	Canada	45.5	-73.5228	13	http://en.wikipedia.org/wiki/Circuit_Gilles_Villeneuve
8	magny_cours	Circuit de Nevers Magny-Cours	Magny Cours	France	46.8642	3.16361	228	http://en.wikipedia.org/wiki/Circuit_de_Nevers_Magny-Cours
9	silverstone	Silverstone Circuit	Silverstone	UK	52.0786	-1.01694	153	http://en.wikipedia.org/wiki/Silverstone_Circuit
10	hockenheimring	Hockenheimring	Hockenheim	Germany	49.3278	8.56583	103	http://en.wikipedia.org/wiki/Hockenheimring
11	hungaroring	Hungaroring	Budapest	Hungary	47.5789	19.2486	264	http://en.wikipedia.org/wiki/Hungaroring
12	valencia	Valencia Street Circuit	Valencia	Spain	39.4589	-0.331667	4	http://en.wikipedia.org/wiki/Valencia_Street_Circuit
13	spa	Circuit de Spa-Francorchamps	Spa	Belgium	50.4372	5.97139	401	http://en.wikipedia.org/wiki/Circuit_de_Spa-Francorchamps
14	monza	Autodromo Nazionale di Monza	Monza	Italy	45.6156	9.28111	162	http://en.wikipedia.org/wiki/Autodromo_Nazionale_Monza
15	marina_bay	Marina Bay Street Circuit	Marina Bay	Singapore	1.2914	103.864	18	http://en.wikipedia.org/wiki/Marina_Bay_Street_Circuit
16	fuji	Fuji Speedway	Oyama	Japan	35.3717	138.927	583	http://en.wikipedia.org/wiki/Fuji_Speedway
17	shanghai	Shanghai International Circuit	Shanghai	China	31.3389	121.22	5	http://en.wikipedia.org/wiki/Shanghai_International_Circuit
18	interlagos	Autódromo José Carlos Pace	São Paulo	Brazil	-23.7036	-46.6997	785	http://en.wikipedia.org/wiki/Aut%C3%B3dromo_Jos%C3%A9_Carlos_Pace
19	indianapolis	Indianapolis Motor Speedway	Indianapolis	USA	39.795	-86.2347	223	http://en.wikipedia.org/wiki/Indianapolis_Motor_Speedway
20	nurburgring	Nürburgring	Nürburg	Germany	50.3356	6.9475	578	http://en.wikipedia.org/wiki/N%C3%BCrburgring
21	imola	Autodromo Enzo e Dino Ferrari	Imola	Italy	44.3439	11.7167	37	http://en.wikipedia.org/wiki/Autodromo_Enzo_e_Dino_Ferrari
22	suzuka	Suzuka Circuit	Suzuka	Japan	34.8431	136.541	45	http://en.wikipedia.org/wiki/Suzuka_Circuit
23	osterreichring	A1-Ring	Spielburg	Austria	47.2197	14.7647	678	http://en.wikipedia.org/wiki/A1-Ring
24	yas_marina	Yas Marina Circuit	Abu Dhabi	UAE	24.4672	54.6031	3	http://en.wikipedia.org/wiki/Yas_Marina_Circuit
25	galvez	Autódromo Juan y Oscar Gálvez	Buenos Aires	Argentina	-34.6943	-58.4593	8	http://en.wikipedia.org/wiki/Aut%C3%B3dromo_Oscar_Alfredo_G%C3%A1lvez
26	jerez	Circuito de Jerez	Jerez de la Frontera	Spain	36.7083	-6.03417	37	http://en.wikipedia.org/wiki/Circuito_Permanente_de_Jerez
27	estoril	Autódromo do Estoril	Estoril	Portugal	38.7506	-9.39417	130	http://en.wikipedia.org/wiki/Aut%C3%B3dromo_do_Estoril
28	okayama	Okayama International Circuit	Okayama	Japan	34.915	134.221	266	http://en.wikipedia.org/wiki/TI_Circuit
29	adelaide	Adelaide Street Circuit	Adelaide	Australia	-34.9272	138.617	58	http://en.wikipedia.org/wiki/Adelaide_Street_Circuit
30	kyalami	Kyalami	Midrand	South Africa	-25.9894	28.0767	1460	http://en.wikipedia.org/wiki/Kyalami
31	donington	Donington Park	Castle Donington	UK	52.8306	-1.37528	88	http://en.wikipedia.org/wiki/Donington_Park
32	rodriguez	Autódromo Hermanos Rodríguez	Mexico City	Mexico	19.4042	-99.0907	2227	http://en.wikipedia.org/wiki/Aut%C3%B3dromo_Hermanos_Rodr%C3%ADguez
33	phoenix	Phoenix street circuit	Phoenix	USA	33.4479	-112.075	345	http://en.wikipedia.org/wiki/Phoenix_street_circuit
34	ricard	Circuit Paul Ricard	Le Castellet	France	43.2506	5.79167	432	http://en.wikipedia.org/wiki/Paul_Ricard_Circuit
35	yeongam	Korean International Circuit	Yeongam County	Korea	34.7333	126.417	0	http://en.wikipedia.org/wiki/Korean_International_Circuit
36	jacarepagua	Autódromo Internacional Nelson Piquet	Rio de Janeiro	Brazil	-22.9756	-43.395	1126	http://en.wikipedia.org/wiki/Aut%C3%B3dromo_Internacional_Nelson_Piquet
37	detroit	Detroit Street Circuit	Detroit	USA	42.3298	-83.0401	177	http://en.wikipedia.org/wiki/Detroit_street_circuit
38	brands_hatch	Brands Hatch	Kent	UK	51.3569	0.263056	145	http://en.wikipedia.org/wiki/Brands_Hatch
39	zandvoort	Circuit Park Zandvoort	Zandvoort	Netherlands	52.3888	4.54092	6	http://en.wikipedia.org/wiki/Circuit_Zandvoort
40	zolder	Zolder	Heusden-Zolder	Belgium	50.9894	5.25694	36	http://en.wikipedia.org/wiki/Zolder
41	dijon	Dijon-Prenois	Dijon	France	47.3625	4.89913	484	http://en.wikipedia.org/wiki/Dijon-Prenois
42	dallas	Fair Park	Dallas	USA	32.7774	-96.7587	139	http://en.wikipedia.org/wiki/Fair_Park
43	long_beach	Long Beach	California	USA	33.7651	-118.189	12	http://en.wikipedia.org/wiki/Long_Beach,_California
44	las_vegas	Las Vegas Street Circuit	Nevada	USA	36.1162	-115.174	639	http://en.wikipedia.org/wiki/Las_Vegas,_Nevada
45	jarama	Jarama	Madrid	Spain	40.6171	-3.58558	609	http://en.wikipedia.org/wiki/Circuito_Permanente_Del_Jarama
46	watkins_glen	Watkins Glen	New York State	USA	42.3369	-76.9272	485	http://en.wikipedia.org/wiki/Watkins_Glen_International
47	anderstorp	Scandinavian Raceway	Anderstorp	Sweden	57.2653	13.6042	153	http://en.wikipedia.org/wiki/Scandinavian_Raceway
48	mosport	Mosport International Raceway	Ontario	Canada	44.0481	-78.6756	332	http://en.wikipedia.org/wiki/Mosport
49	montjuic	Montjuïc	Barcelona	Spain	41.3664	2.15167	79	http://en.wikipedia.org/wiki/Montju%C3%AFc_circuit
50	nivelles	Nivelles-Baulers	Brussels	Belgium	50.6211	4.32694	139	http://en.wikipedia.org/wiki/Nivelles-Baulers
51	charade	Charade Circuit	Clermont-Ferrand	France	45.7472	3.03889	790	http://en.wikipedia.org/wiki/Charade_Circuit
52	tremblant	Circuit Mont-Tremblant	Quebec	Canada	46.1877	-74.6099	214	http://en.wikipedia.org/wiki/Circuit_Mont-Tremblant
53	essarts	Rouen-Les-Essarts	Rouen	France	49.3306	1.00458	81	http://en.wikipedia.org/wiki/Rouen-Les-Essarts
54	lemans	Le Mans	Le Mans	France	47.95	0.224231	67	http://en.wikipedia.org/wiki/Circuit_de_la_Sarthe#Bugatti_Circuit
55	reims	Reims-Gueux	Reims	France	49.2542	3.93083	88	http://en.wikipedia.org/wiki/Reims-Gueux
56	george	Prince George Circuit	Eastern Cape Province	South Africa	-33.0486	27.8736	15	http://en.wikipedia.org/wiki/Prince_George_Circuit
57	zeltweg	Zeltweg	Styria	Austria	47.2039	14.7478	676	http://en.wikipedia.org/wiki/Zeltweg_Airfield
58	aintree	Aintree	Liverpool	UK	53.4769	-2.94056	20	http://en.wikipedia.org/wiki/Aintree_Motor_Racing_Circuit
59	boavista	Circuito da Boavista	Oporto	Portugal	41.1705	-8.67325	28	http://en.wikipedia.org/wiki/Circuito_da_Boavista
60	riverside	Riverside International Raceway	California	USA	33.937	-117.273	470	http://en.wikipedia.org/wiki/Riverside_International_Raceway
61	avus	AVUS	Berlin	Germany	52.4806	13.2514	53	http://en.wikipedia.org/wiki/AVUS
62	monsanto	Monsanto Park Circuit	Lisbon	Portugal	38.7197	-9.20306	158	http://en.wikipedia.org/wiki/Monsanto_Park_Circuit
63	sebring	Sebring International Raceway	Florida	USA	27.4547	-81.3483	18	http://en.wikipedia.org/wiki/Sebring_Raceway
64	ain-diab	Ain Diab	Casablanca	Morocco	33.5786	-7.6875	19	http://en.wikipedia.org/wiki/Ain-Diab_Circuit
65	pescara	Pescara Circuit	Pescara	Italy	42.475	14.1508	129	http://en.wikipedia.org/wiki/Pescara_Circuit
66	bremgarten	Circuit Bremgarten	Bern	Switzerland	46.9589	7.40194	551	http://en.wikipedia.org/wiki/Circuit_Bremgarten
67	pedralbes	Circuit de Pedralbes	Barcelona	Spain	41.3903	2.11667	85	http://en.wikipedia.org/wiki/Pedralbes_Circuit
68	buddh	Buddh International Circuit	Uttar Pradesh	India	28.3487	77.5331	194	http://en.wikipedia.org/wiki/Buddh_International_Circuit
69	americas	Circuit of the Americas	Austin	USA	30.1328	-97.6411	161	http://en.wikipedia.org/wiki/Circuit_of_the_Americas
70	red_bull_ring	Red Bull Ring	Spielburg	Austria	47.2197	14.7647	678	http://en.wikipedia.org/wiki/Red_Bull_Ring
71	sochi	Sochi Autodrom	Sochi	Russia	43.4057	39.9578	2	http://en.wikipedia.org/wiki/Sochi_Autodrom
72	port_imperial	Port Imperial Street Circuit	New Jersey	USA	40.7769	-74.0111	4	http://en.wikipedia.org/wiki/Port_Imperial_Street_Circuit
73	BAK	Baku City Circuit	Baku	Azerbaijan	40.3725	49.8533	-7	http://en.wikipedia.org/wiki/Baku_City_Circuit
74	hanoi	Hanoi Street Circuit	Hanoi	Vietnam	21.0166	105.766	9	http://en.wikipedia.org/wiki/Hanoi_Street_Circuit
75	portimao	Autódromo Internacional do Algarve	Portimão	Portugal	37.227	-8.6267	108	http://en.wikipedia.org/wiki/Algarve_International_Circuit
76	mugello	Autodromo Internazionale del Mugello	Mugello	Italy	43.9975	11.3719	255	http://en.wikipedia.org/wiki/Mugello_Circuit
77	jeddah	Jeddah Street Circuit	Jeddah	Saudi Arabia	21.5433	39.1728	15	http://en.wikipedia.org/wiki/Jeddah_Street_Circuit
\.


--
-- Data for Name: fact_constructors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_constructors (constructor_id, constructor_ref, constructors_name, nationality, url, color_code_hex, color_code_rgb) FROM stdin;
2	bmw_sauber	BMW Sauber	German	http://en.wikipedia.org/wiki/BMW_Sauber	\N	\N
7	toyota	Toyota	Japanese	http://en.wikipedia.org/wiki/Toyota_Racing	\N	\N
8	super_aguri	Super Aguri	Japanese	http://en.wikipedia.org/wiki/Super_Aguri_F1	\N	\N
11	honda	Honda	Japanese	http://en.wikipedia.org/wiki/Honda_Racing_F1	\N	\N
12	spyker	Spyker	Dutch	http://en.wikipedia.org/wiki/Spyker_F1	\N	\N
13	mf1	MF1	Russian	http://en.wikipedia.org/wiki/Midland_F1_Racing	\N	\N
14	spyker_mf1	Spyker MF1	Dutch	http://en.wikipedia.org/wiki/Midland_F1_Racing	\N	\N
16	bar	BAR	British	http://en.wikipedia.org/wiki/British_American_Racing	\N	\N
17	jordan	Jordan	Irish	http://en.wikipedia.org/wiki/Jordan_Grand_Prix	\N	\N
18	minardi	Minardi	Italian	http://en.wikipedia.org/wiki/Minardi	\N	\N
19	jaguar	Jaguar	British	http://en.wikipedia.org/wiki/Jaguar_Racing	\N	\N
20	prost	Prost	French	http://en.wikipedia.org/wiki/Prost_Grand_Prix	\N	\N
21	arrows	Arrows	British	http://en.wikipedia.org/wiki/Arrows_Grand_Prix_International	\N	\N
22	benetton	Benetton	Italian	http://en.wikipedia.org/wiki/Benetton_Formula	\N	\N
23	brawn	Brawn	British	http://en.wikipedia.org/wiki/Brawn_GP	\N	\N
24	stewart	Stewart	British	http://en.wikipedia.org/wiki/Stewart_Grand_Prix	\N	\N
25	tyrrell	Tyrrell	British	http://en.wikipedia.org/wiki/Tyrrell_Racing	\N	\N
26	lola	Lola	British	http://en.wikipedia.org/wiki/MasterCard_Lola	\N	\N
27	ligier	Ligier	French	http://en.wikipedia.org/wiki/Ligier	\N	\N
28	forti	Forti	Italian	http://en.wikipedia.org/wiki/Forti	\N	\N
29	footwork	Footwork	British	http://en.wikipedia.org/wiki/Footwork_Arrows	\N	\N
30	pacific	Pacific	British	http://en.wikipedia.org/wiki/Pacific_Racing	\N	\N
31	simtek	Simtek	British	http://en.wikipedia.org/wiki/Simtek	\N	\N
33	larrousse	Larrousse	French	http://en.wikipedia.org/wiki/Larrousse	\N	\N
34	brabham	Brabham	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
35	dallara	Dallara	Italian	http://en.wikipedia.org/wiki/Dallara	\N	\N
36	fondmetal	Fondmetal	Italian	http://en.wikipedia.org/wiki/Fondmetal	\N	\N
37	march	March	British	http://en.wikipedia.org/wiki/March_Engineering	\N	\N
38	moda	Andrea Moda	Italian	http://en.wikipedia.org/wiki/Andrea_Moda_Formula	\N	\N
39	ags	AGS	French	http://en.wikipedia.org/wiki/Automobiles_Gonfaronnaises_Sportives	\N	\N
40	lambo	Lambo	Italian	http://en.wikipedia.org/wiki/Modena_(racing_team)	\N	\N
41	leyton	Leyton House	British	http://en.wikipedia.org/wiki/Leyton_House	\N	\N
42	coloni	Coloni	Italian	http://en.wikipedia.org/wiki/Enzo_Coloni_Racing_Car_Systems	\N	\N
44	eurobrun	Euro Brun	Italian	http://en.wikipedia.org/wiki/Euro_Brun	\N	\N
45	osella	Osella	Italian	http://en.wikipedia.org/wiki/Osella	\N	\N
46	onyx	Onyx	British	http://en.wikipedia.org/wiki/Onyx_(racing_team)	\N	\N
47	life	Life	Italian	http://en.wikipedia.org/wiki/Life_(Racing_Team)	\N	\N
48	rial	Rial	German	http://en.wikipedia.org/wiki/Rial_%28racing_team%29	\N	\N
49	zakspeed	Zakspeed	German	http://en.wikipedia.org/wiki/Zakspeed	\N	\N
50	ram	RAM	British	http://en.wikipedia.org/wiki/RAM_Racing	\N	\N
52	spirit	Spirit	British	http://en.wikipedia.org/wiki/Spirit_(racing_team)	\N	\N
53	toleman	Toleman	British	http://en.wikipedia.org/wiki/Toleman	\N	\N
54	ats	ATS	Italian	http://en.wikipedia.org/wiki/ATS_(wheels)	\N	\N
55	theodore	Theodore	Hong Kong	http://en.wikipedia.org/wiki/Theodore_Racing	\N	\N
56	fittipaldi	Fittipaldi	Brazilian	http://en.wikipedia.org/wiki/Fittipaldi_%28constructor%29	\N	\N
57	ensign	Ensign	British	http://en.wikipedia.org/wiki/Ensign_%28racing_team%29	\N	\N
58	shadow	Shadow	British	http://en.wikipedia.org/wiki/Shadow_Racing_Cars	\N	\N
59	wolf	Wolf	Canadian	http://en.wikipedia.org/wiki/Walter_Wolf_Racing	\N	\N
60	merzario	Merzario	Italian	http://en.wikipedia.org/wiki/Merzario	\N	\N
61	kauhsen	Kauhsen	German	http://en.wikipedia.org/wiki/Kauhsen	\N	\N
62	rebaque	Rebaque	Mexican	http://en.wikipedia.org/wiki/Rebaque	\N	\N
63	surtees	Surtees	British	http://en.wikipedia.org/wiki/Surtees	\N	\N
64	hesketh	Hesketh	British	http://en.wikipedia.org/wiki/Hesketh_Racing	\N	\N
65	martini	Martini	French	http://en.wikipedia.org/wiki/Martini_(cars)	\N	\N
66	brm	BRM	British	http://en.wikipedia.org/wiki/BRM	\N	\N
67	penske	Penske	American	http://en.wikipedia.org/wiki/Penske_Racing	\N	\N
68	lec	LEC	British	http://en.wikipedia.org/wiki/LEC_(Formula_One)	\N	\N
69	mcguire	McGuire	Australian	http://en.wikipedia.org/wiki/McGuire_(Formula_One)	\N	\N
70	boro	Boro	Dutch	http://en.wikipedia.org/wiki/Boro_(Formula_One)	\N	\N
71	apollon	Apollon	Swiss	http://en.wikipedia.org/wiki/Apollon_(Formula_One)	\N	\N
72	kojima	Kojima	Japanese	http://en.wikipedia.org/wiki/Kojima_Engineering	\N	\N
73	parnelli	Parnelli	American	http://en.wikipedia.org/wiki/Parnelli	\N	\N
74	maki	Maki	Japanese	http://en.wikipedia.org/wiki/Maki_(cars)	\N	\N
75	hill	Embassy Hill	British	http://en.wikipedia.org/wiki/Hill_(constructor)	\N	\N
76	lyncar	Lyncar	British	http://en.wikipedia.org/wiki/Lyncar	\N	\N
77	trojan	Trojan	British	http://en.wikipedia.org/wiki/Trojan_(Racing_team)	\N	\N
78	amon	Amon	New Zealand	http://en.wikipedia.org/wiki/Amon_(Formula_One_team)	\N	\N
79	token	Token	British	http://en.wikipedia.org/wiki/Token_(Racing_team)	\N	\N
80	iso_marlboro	Iso Marlboro	British	http://en.wikipedia.org/wiki/Iso_Marlboro	\N	\N
81	tecno	Tecno	Italian	http://en.wikipedia.org/wiki/Tecno	\N	\N
1	mclaren	McLaren	British	http://en.wikipedia.org/wiki/McLaren	#FF8700	\N
82	matra	Matra	French	http://en.wikipedia.org/wiki/Matra	\N	\N
83	politoys	Politoys	British	http://en.wikipedia.org/wiki/Frank_Williams_Racing_Cars	\N	\N
84	connew	Connew	British	http://en.wikipedia.org/wiki/Connew	\N	\N
85	bellasi	Bellasi	Swiss	http://en.wikipedia.org/wiki/Bellasi	\N	\N
86	tomaso	De Tomaso	Italian	http://en.wikipedia.org/wiki/De_Tomaso	\N	\N
87	cooper	Cooper	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
88	eagle	Eagle	American	http://en.wikipedia.org/wiki/Anglo_American_Racers	\N	\N
89	lds	LDS	South African	http://en.wikipedia.org/wiki/LDS_(automobile)	\N	\N
90	protos	Protos	British	http://en.wikipedia.org/wiki/Protos_(constructor)	\N	\N
91	shannon	Shannon	British	http://en.wikipedia.org/wiki/Shannon_(Formula_One)	\N	\N
92	scirocco	Scirocco	British	http://en.wikipedia.org/wiki/Scirocco-Powell	\N	\N
93	re	RE	Rhodesian	http://en.wikipedia.org/wiki/RE_%28automobile%29	\N	\N
94	brp	BRP	British	http://en.wikipedia.org/wiki/British_Racing_Partnership	\N	\N
95	porsche	Porsche	German	http://en.wikipedia.org/wiki/Porsche_in_Formula_One	\N	\N
96	derrington	Derrington	British	http://en.wikipedia.org/wiki/Derrington-Francis	\N	\N
97	gilby	Gilby	British	http://en.wikipedia.org/wiki/Gilby	\N	\N
98	stebro	Stebro	Canadian	http://en.wikipedia.org/wiki/Stebro	\N	\N
99	emeryson	Emeryson	British	http://en.wikipedia.org/wiki/Emeryson	\N	\N
100	enb	ENB	Belgium	http://en.wikipedia.org/wiki/Ecurie_Nationale_Belge	\N	\N
101	jbw	JBW	British	http://en.wikipedia.org/wiki/JBW	\N	\N
102	ferguson	Ferguson	British	http://en.wikipedia.org/wiki/Ferguson_Research_Ltd.	\N	\N
103	mbm	MBM	Swiss	http://en.wikipedia.org/wiki/Monteverdi_Basel_Motors	\N	\N
104	behra-porsche	Behra-Porsche	Italian	http://en.wikipedia.org/wiki/Behra-Porsche	\N	\N
105	maserati	Maserati	Italian	http://en.wikipedia.org/wiki/Maserati	\N	\N
106	scarab	Scarab	American	http://en.wikipedia.org/wiki/Scarab_(constructor)	\N	\N
107	watson	Watson	American	http://en.wikipedia.org/wiki/A.J._Watson	\N	\N
108	epperly	Epperly	American	http://en.wikipedia.org/wiki/Epperly	\N	\N
109	phillips	Phillips	American	http://en.wikipedia.org/wiki/Phillips_(constructor)	\N	\N
110	lesovsky	Lesovsky	American	http://en.wikipedia.org/wiki/Lesovsky	\N	\N
111	trevis	Trevis	American	http://en.wikipedia.org/wiki/Trevis	\N	\N
112	meskowski	Meskowski	American	http://en.wikipedia.org/wiki/Meskowski	\N	\N
113	kurtis_kraft	Kurtis Kraft	American	http://en.wikipedia.org/wiki/Kurtis_Kraft	\N	\N
114	kuzma	Kuzma	American	http://en.wikipedia.org/wiki/Kuzma_(constructor)	\N	\N
115	vhristensen	Christensen	American	http://en.wikipedia.org/wiki/Christensen_(constructor)	\N	\N
116	ewing	Ewing	American	http://en.wikipedia.org/wiki/Ewing_(constructor)	\N	\N
117	aston_martin	Aston Martin	British	http://en.wikipedia.org/wiki/Aston_Martin	\N	\N
118	vanwall	Vanwall	British	http://en.wikipedia.org/wiki/Vanwall	\N	\N
119	moore	Moore	American	http://en.wikipedia.org/wiki/Moore_(constructor)	\N	\N
120	dunn	Dunn	American	http://en.wikipedia.org/wiki/Dunn_Engineering	\N	\N
121	elder	Elder	American	http://en.wikipedia.org/wiki/Elder_(constructor)	\N	\N
122	sutton	Sutton	American	http://en.wikipedia.org/wiki/Sutton_(constructor)	\N	\N
123	fry	Fry	British	http://en.wikipedia.org/wiki/Fry_(racing_team)	\N	\N
124	tec-mec	Tec-Mec	Italian	http://en.wikipedia.org/wiki/Tec-Mec	\N	\N
125	connaught	Connaught	British	http://en.wikipedia.org/wiki/Connaught_Engineering	\N	\N
126	alta	Alta	British	http://en.wikipedia.org/wiki/Alta_auto_racing_team	\N	\N
127	osca	OSCA	Italian	http://en.wikipedia.org/wiki/Officine_Specializate_Costruzione_Automobili	\N	\N
128	gordini	Gordini	French	http://en.wikipedia.org/wiki/Gordini	\N	\N
129	stevens	Stevens	American	http://en.wikipedia.org/wiki/Stevens_(constructor)	\N	\N
130	bugatti	Bugatti	French	http://en.wikipedia.org/wiki/Bugatti	\N	\N
132	lancia	Lancia	Italian	http://en.wikipedia.org/wiki/Lancia_in_Formula_One	\N	\N
133	hwm	HWM	British	http://en.wikipedia.org/wiki/Hersham_and_Walton_Motors	\N	\N
134	schroeder	Schroeder	American	http://en.wikipedia.org/wiki/Schroeder_(constructor)	\N	\N
135	pawl	Pawl	American	http://en.wikipedia.org/wiki/Pawl_(constructor)	\N	\N
136	pankratz	Pankratz	American	http://en.wikipedia.org/wiki/Pankratz	\N	\N
137	arzani-volpini	Arzani-Volpini	Italian	http://en.wikipedia.org/wiki/Arzani-Volpini	\N	\N
138	nichels	Nichels	American	http://en.wikipedia.org/wiki/Nichels	\N	\N
139	bromme	Bromme	American	http://en.wikipedia.org/wiki/Bromme	\N	\N
140	klenk	Klenk	German	http://en.wikipedia.org/wiki/Klenk	\N	\N
141	simca	Simca	French	http://en.wikipedia.org/wiki/Simca	\N	\N
142	turner	Turner	American	http://en.wikipedia.org/wiki/Turner_(constructor)	\N	\N
143	del_roy	Del Roy	American	http://en.wikipedia.org/wiki/Del_Roy	\N	\N
144	veritas	Veritas	German	http://en.wikipedia.org/wiki/Veritas_(constructor)	\N	\N
145	bmw	BMW	German	http://en.wikipedia.org/wiki/BMW	\N	\N
146	emw	EMW	East German	http://en.wikipedia.org/wiki/Eisenacher_Motorenwerk	\N	\N
147	afm	AFM	German	http://en.wikipedia.org/wiki/Alex_von_Falkenhausen_Motorenbau	\N	\N
148	frazer_nash	Frazer Nash	British	http://en.wikipedia.org/wiki/Frazer_Nash	\N	\N
149	sherman	Sherman	American	http://en.wikipedia.org/wiki/Sherman_(constructor)	\N	\N
150	deidt	Deidt	American	http://en.wikipedia.org/wiki/Deidt	\N	\N
151	era	ERA	British	http://en.wikipedia.org/wiki/English_Racing_Automobiles	\N	\N
152	butterworth	Aston Butterworth	British	http://en.wikipedia.org/wiki/Aston_Butterworth	\N	\N
153	cisitalia	Cisitalia	Italian	http://en.wikipedia.org/wiki/Cisitalia	\N	\N
154	lago	Talbot-Lago	French	http://en.wikipedia.org/wiki/Talbot-Lago	\N	\N
155	hall	Hall	American	http://en.wikipedia.org/wiki/Hall_(constructor)	\N	\N
156	marchese	Marchese	American	http://en.wikipedia.org/wiki/Marchese_(constructor)	\N	\N
157	langley	Langley	American	http://en.wikipedia.org/wiki/Langley_(constructor)	\N	\N
158	rae	Rae	American	http://en.wikipedia.org/wiki/Rae_(motorsport)	\N	\N
159	olson	Olson	American	http://en.wikipedia.org/wiki/Olson_(constructor)	\N	\N
160	wetteroth	Wetteroth	American	http://en.wikipedia.org/wiki/Wetteroth	\N	\N
161	adams	Adams	American	http://en.wikipedia.org/wiki/Adams_(constructor)	\N	\N
162	snowberger	Snowberger	American	http://en.wikipedia.org/wiki/Snowberger	\N	\N
163	milano	Milano	Italian	http://en.wikipedia.org/wiki/Scuderia_Milano	\N	\N
164	hrt	HRT	Spanish	http://en.wikipedia.org/wiki/Hispania_Racing	\N	\N
167	cooper-maserati	Cooper-Maserati	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
166	virgin	Virgin	British	http://en.wikipedia.org/wiki/Virgin_Racing	\N	\N
168	cooper-osca	Cooper-OSCA	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
169	cooper-borgward	Cooper-Borgward	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
170	cooper-climax	Cooper-Climax	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
171	cooper-castellotti	Cooper-Castellotti	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
174	de_tomaso-osca	De Tomaso-Osca	Italian	http://en.wikipedia.org/wiki/De_Tomaso	\N	\N
178	cooper-alfa_romeo	Cooper-Alfa Romeo	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
181	brabham-brm	Brabham-BRM	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
182	brabham-ford	Brabham-Ford	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
183	brabham-climax	Brabham-Climax	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
184	lds-climax	LDS-Climax	South African	http://en.wikipedia.org/wiki/LDS_(automobile)	\N	\N
185	lds-alfa_romeo	LDS-Alfa Romeo	South African	http://en.wikipedia.org/wiki/LDS_(automobile)	\N	\N
186	cooper-ford	Cooper-Ford	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
189	eagle-climax	Eagle-Climax	American	http://en.wikipedia.org/wiki/Anglo_American_Racers	\N	\N
190	eagle-weslake	Eagle-Weslake	American	http://en.wikipedia.org/wiki/Anglo_American_Racers	\N	\N
191	brabham-repco	Brabham-Repco	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
193	cooper-ats	Cooper-ATS	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
195	cooper-brm	Cooper-BRM	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	\N	\N
196	matra-ford	Matra-Ford	French	http://en.wikipedia.org/wiki/Matra	\N	\N
197	brm-ford	BRM-Ford	British	http://en.wikipedia.org/wiki/BRM	\N	\N
198	mclaren-alfa_romeo	McLaren-Alfa Romeo	British	http://en.wikipedia.org/wiki/McLaren_(racing)	\N	\N
199	march-alfa_romeo	March-Alfa Romeo	British	http://en.wikipedia.org/wiki/March_Engineering	\N	\N
200	march-ford	March-Ford	British	http://en.wikipedia.org/wiki/March_Engineering	\N	\N
201	lotus-pw	Lotus-Pratt &amp; Whitney	British	http://en.wikipedia.org/wiki/Team_Lotus	\N	\N
202	shadow-ford	Shadow-Ford	British	http://en.wikipedia.org/wiki/Shadow_Racing_Cars	\N	\N
203	shadow-matra	Shadow-Matra	British	http://en.wikipedia.org/wiki/Shadow_Racing_Cars	\N	\N
204	brabham-alfa_romeo	Brabham-Alfa Romeo	British	http://en.wikipedia.org/wiki/Brabham	\N	\N
205	lotus_racing	Lotus	Malaysian	http://en.wikipedia.org/wiki/Lotus_Racing	\N	\N
206	marussia	Marussia	Russian	http://en.wikipedia.org/wiki/Marussia_F1	\N	\N
207	caterham	Caterham	Malaysian	http://en.wikipedia.org/wiki/Caterham_F1	\N	\N
208	lotus_f1	Lotus F1	British	http://en.wikipedia.org/wiki/Lotus_F1	\N	\N
209	manor	Manor Marussia	British	http://en.wikipedia.org/wiki/Manor_Motorsport	\N	\N
212	alpha_tauri	Scuderia Alpha Tauri	Italian	http://en.wikipedia.org/wiki/Scuderia_Alpha_Tauri	\N	\N
3	williams	Williams	British	http://en.wikipedia.org/wiki/Williams_Grand_Prix_Engineering	#005AFF	0,90,255
5	toro_rosso	Toro Rosso	Italian	http://en.wikipedia.org/wiki/Scuderia_Toro_Rosso	#469BFF	70,155,255
6	ferrari	Ferrari	Italian	http://en.wikipedia.org/wiki/Scuderia_Ferrari	#DC0000	220,0,0
9	red_bull	Red Bull	Austrian	http://en.wikipedia.org/wiki/Red_Bull_Racing	#0600EF	6,0,239
10	force_india	Force India	Indian	http://en.wikipedia.org/wiki/Racing_Point_Force_India	#F596C8	245,150,200
15	sauber	Sauber	Swiss	http://en.wikipedia.org/wiki/Sauber	#9B0000	155,0,0
32	team_lotus	Team Lotus	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
51	alfa	Alfa Romeo	Italian	http://en.wikipedia.org/wiki/Alfa_Romeo_in_Formula_One	#900000	144,0,0
131	mercedes	Mercedes	German	http://en.wikipedia.org/wiki/Mercedes-Benz_in_Formula_One	#00D2BE	0,210,90
172	lotus-climax	Lotus-Climax	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
173	lotus-maserati	Lotus-Maserati	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
175	de_tomaso-alfa_romeo	De Tomaso-Alfa Romeo	Italian	http://en.wikipedia.org/wiki/De_Tomaso	#900000	144,0,0
4	renault	Renault	French	http://en.wikipedia.org/wiki/Renault_in_Formula_One	#FFF500	255,245,0
176	lotus-brm	Lotus-BRM	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
177	lotus-borgward	Lotus-Borgward	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
179	de_tomaso-ferrari	De Tomaso-Ferrari	Italian	http://en.wikipedia.org/wiki/De_Tomaso	#DC0000	220,0,0
180	lotus-ford	Lotus-Ford	British	http://en.wikipedia.org/wiki/Team_Lotus	#FFB800	255,184,0
187	mclaren-ford	McLaren-Ford	British	http://en.wikipedia.org/wiki/Team_McLaren	#FF8700	255,135,0
188	mclaren-seren	McLaren-Serenissima	British	http://en.wikipedia.org/wiki/Team_McLaren	#FF8700	255,135,0
192	cooper-ferrari	Cooper-Ferrari	British	http://en.wikipedia.org/wiki/Cooper_Car_Company	#DC0000	220,0,0
194	mclaren-brm	McLaren-BRM	British	http://en.wikipedia.org/wiki/McLaren_(racing)	#FF8700	255,135,0
210	haas	Haas F1 Team	American	http://en.wikipedia.org/wiki/Haas_F1_Team	#FFFFFF	255,255,255
211	racing_point	Racing Point	British	http://en.wikipedia.org/wiki/Racing_Point_F1_Team	#F596C8	245,150,200
213	alphatauri	AlphaTauri	Italian	http://en.wikipedia.org/wiki/Scuderia_AlphaTauri	#2B4562	43,69,98
\.


--
-- Data for Name: fact_drivers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_drivers (driver_id, driver_ref, driver_number, name_tag, firstname, lastname, dob, nationality, url) FROM stdin;
1	hamilton	44	HAM	Lewis	Hamilton	1985-01-07	British	http://en.wikipedia.org/wiki/Lewis_Hamilton
2	heidfeld	\N	HEI	Nick	Heidfeld	1977-05-10	German	http://en.wikipedia.org/wiki/Nick_Heidfeld
3	rosberg	6	ROS	Nico	Rosberg	1985-06-27	German	http://en.wikipedia.org/wiki/Nico_Rosberg
4	alonso	14	ALO	Fernando	Alonso	1981-07-29	Spanish	http://en.wikipedia.org/wiki/Fernando_Alonso
5	kovalainen	\N	KOV	Heikki	Kovalainen	1981-10-19	Finnish	http://en.wikipedia.org/wiki/Heikki_Kovalainen
6	nakajima	\N	NAK	Kazuki	Nakajima	1985-01-11	Japanese	http://en.wikipedia.org/wiki/Kazuki_Nakajima
7	bourdais	\N	BOU	Sébastien	Bourdais	1979-02-28	French	http://en.wikipedia.org/wiki/S%C3%A9bastien_Bourdais
8	raikkonen	7	RAI	Kimi	Räikkönen	1979-10-17	Finnish	http://en.wikipedia.org/wiki/Kimi_R%C3%A4ikk%C3%B6nen
9	kubica	88	KUB	Robert	Kubica	1984-12-07	Polish	http://en.wikipedia.org/wiki/Robert_Kubica
10	glock	\N	GLO	Timo	Glock	1982-03-18	German	http://en.wikipedia.org/wiki/Timo_Glock
11	sato	\N	SAT	Takuma	Sato	1977-01-28	Japanese	http://en.wikipedia.org/wiki/Takuma_Sato
12	piquet_jr	\N	PIQ	Nelson	Piquet Jr.	1985-07-25	Brazilian	http://en.wikipedia.org/wiki/Nelson_Piquet,_Jr.
13	massa	19	MAS	Felipe	Massa	1981-04-25	Brazilian	http://en.wikipedia.org/wiki/Felipe_Massa
14	coulthard	\N	COU	David	Coulthard	1971-03-27	British	http://en.wikipedia.org/wiki/David_Coulthard
15	trulli	\N	TRU	Jarno	Trulli	1974-07-13	Italian	http://en.wikipedia.org/wiki/Jarno_Trulli
16	sutil	99	SUT	Adrian	Sutil	1983-01-11	German	http://en.wikipedia.org/wiki/Adrian_Sutil
17	webber	\N	WEB	Mark	Webber	1976-08-27	Australian	http://en.wikipedia.org/wiki/Mark_Webber
18	button	22	BUT	Jenson	Button	1980-01-19	British	http://en.wikipedia.org/wiki/Jenson_Button
19	davidson	\N	DAV	Anthony	Davidson	1979-04-18	British	http://en.wikipedia.org/wiki/Anthony_Davidson
20	vettel	5	VET	Sebastian	Vettel	1987-07-03	German	http://en.wikipedia.org/wiki/Sebastian_Vettel
21	fisichella	\N	FIS	Giancarlo	Fisichella	1973-01-14	Italian	http://en.wikipedia.org/wiki/Giancarlo_Fisichella
22	barrichello	\N	BAR	Rubens	Barrichello	1972-05-23	Brazilian	http://en.wikipedia.org/wiki/Rubens_Barrichello
23	ralf_schumacher	\N	SCH	Ralf	Schumacher	1975-06-30	German	http://en.wikipedia.org/wiki/Ralf_Schumacher
24	liuzzi	\N	LIU	Vitantonio	Liuzzi	1980-08-06	Italian	http://en.wikipedia.org/wiki/Vitantonio_Liuzzi
25	wurz	\N	WUR	Alexander	Wurz	1974-02-15	Austrian	http://en.wikipedia.org/wiki/Alexander_Wurz
26	speed	\N	SPE	Scott	Speed	1983-01-24	American	http://en.wikipedia.org/wiki/Scott_Speed
27	albers	\N	ALB	Christijan	Albers	1979-04-16	Dutch	http://en.wikipedia.org/wiki/Christijan_Albers
28	markus_winkelhock	\N	WIN	Markus	Winkelhock	1980-06-13	German	http://en.wikipedia.org/wiki/Markus_Winkelhock
29	yamamoto	\N	YAM	Sakon	Yamamoto	1982-07-09	Japanese	http://en.wikipedia.org/wiki/Sakon_Yamamoto
30	michael_schumacher	\N	MSC	Michael	Schumacher	1969-01-03	German	http://en.wikipedia.org/wiki/Michael_Schumacher
31	montoya	\N	MON	Juan	Pablo Montoya	1975-09-20	Colombian	http://en.wikipedia.org/wiki/Juan_Pablo_Montoya
32	klien	\N	KLI	Christian	Klien	1983-02-07	Austrian	http://en.wikipedia.org/wiki/Christian_Klien
33	monteiro	\N	TMO	Tiago	Monteiro	1976-07-24	Portuguese	http://en.wikipedia.org/wiki/Tiago_Monteiro
34	ide	\N	IDE	Yuji	Ide	1975-01-21	Japanese	http://en.wikipedia.org/wiki/Yuji_Ide
35	villeneuve	\N	VIL	Jacques	Villeneuve	1971-04-09	Canadian	http://en.wikipedia.org/wiki/Jacques_Villeneuve
36	montagny	\N	FMO	Franck	Montagny	1978-01-05	French	http://en.wikipedia.org/wiki/Franck_Montagny
37	rosa	\N	DLR	Pedro	de la Rosa	1971-02-24	Spanish	http://en.wikipedia.org/wiki/Pedro_de_la_Rosa
38	doornbos	\N	DOO	Robert	Doornbos	1981-09-23	Dutch	http://en.wikipedia.org/wiki/Robert_Doornbos
39	karthikeyan	\N	KAR	Narain	Karthikeyan	1977-01-14	Indian	http://en.wikipedia.org/wiki/Narain_Karthikeyan
40	friesacher	\N	FRI	Patrick	Friesacher	1980-09-26	Austrian	http://en.wikipedia.org/wiki/Patrick_Friesacher
41	zonta	\N	ZON	Ricardo	Zonta	1976-03-23	Brazilian	http://en.wikipedia.org/wiki/Ricardo_Zonta
42	pizzonia	\N	PIZ	Antônio	Pizzonia	1980-09-11	Brazilian	http://en.wikipedia.org/wiki/Ant%C3%B4nio_Pizzonia
43	matta	\N	\N	Cristiano	da Matta	1973-09-19	Brazilian	http://en.wikipedia.org/wiki/Cristiano_da_Matta
44	panis	\N	\N	Olivier	Panis	1966-09-02	French	http://en.wikipedia.org/wiki/Olivier_Panis
45	pantano	\N	\N	Giorgio	Pantano	1979-02-04	Italian	http://en.wikipedia.org/wiki/Giorgio_Pantano
46	bruni	\N	\N	Gianmaria	Bruni	1981-05-30	Italian	http://en.wikipedia.org/wiki/Gianmaria_Bruni
47	baumgartner	\N	\N	Zsolt	Baumgartner	1981-01-01	Hungarian	http://en.wikipedia.org/wiki/Zsolt_Baumgartner
48	gene	\N	\N	Marc	Gené	1974-03-29	Spanish	http://en.wikipedia.org/wiki/Marc_Gen%C3%A9
49	frentzen	\N	\N	Heinz-Harald	Frentzen	1967-05-18	German	http://en.wikipedia.org/wiki/Heinz-Harald_Frentzen
50	verstappen	\N	\N	Jos	Verstappen	1972-03-04	Dutch	http://en.wikipedia.org/wiki/Jos_Verstappen
51	wilson	\N	\N	Justin	Wilson	1978-07-31	British	http://en.wikipedia.org/wiki/Justin_Wilson_(racing_driver)
52	firman	\N	\N	Ralph	Firman	1975-05-20	Irish	http://en.wikipedia.org/wiki/Ralph_Firman
53	kiesa	\N	\N	Nicolas	Kiesa	1978-03-03	Danish	http://en.wikipedia.org/wiki/Nicolas_Kiesa
54	burti	\N	\N	Luciano	Burti	1975-03-05	Brazilian	http://en.wikipedia.org/wiki/Luciano_Burti
55	alesi	\N	\N	Jean	Alesi	1964-06-11	French	http://en.wikipedia.org/wiki/Jean_Alesi
56	irvine	\N	\N	Eddie	Irvine	1965-11-10	British	http://en.wikipedia.org/wiki/Eddie_Irvine
57	hakkinen	\N	\N	Mika	Häkkinen	1968-09-28	Finnish	http://en.wikipedia.org/wiki/Mika_H%C3%A4kkinen
58	marques	\N	\N	Tarso	Marques	1976-01-19	Brazilian	http://en.wikipedia.org/wiki/Tarso_Marques
59	bernoldi	\N	\N	Enrique	Bernoldi	1978-10-19	Brazilian	http://en.wikipedia.org/wiki/Enrique_Bernoldi
60	mazzacane	\N	\N	Gastón	Mazzacane	1975-05-08	Argentine	http://en.wikipedia.org/wiki/Gast%C3%B3n_Mazzacane
61	enge	\N	\N	Tomáš	Enge	1976-09-11	Czech	http://en.wikipedia.org/wiki/Tom%C3%A1%C5%A1_Enge
62	yoong	\N	\N	Alex	Yoong	1976-07-20	Malaysian	http://en.wikipedia.org/wiki/Alex_Yoong
63	salo	\N	\N	Mika	Salo	1966-11-30	Finnish	http://en.wikipedia.org/wiki/Mika_Salo
64	diniz	\N	\N	Pedro	Diniz	1970-05-22	Brazilian	http://en.wikipedia.org/wiki/Pedro_Diniz
65	herbert	\N	\N	Johnny	Herbert	1964-06-25	British	http://en.wikipedia.org/wiki/Johnny_Herbert
66	mcnish	\N	\N	Allan	McNish	1969-12-29	British	http://en.wikipedia.org/wiki/Allan_McNish
67	buemi	\N	BUE	Sébastien	Buemi	1988-10-31	Swiss	http://en.wikipedia.org/wiki/S%C3%A9bastien_Buemi
68	takagi	\N	\N	Toranosuke	Takagi	1974-02-12	Japanese	http://en.wikipedia.org/wiki/Toranosuke_Takagi
69	badoer	\N	BAD	Luca	Badoer	1971-01-25	Italian	http://en.wikipedia.org/wiki/Luca_Badoer
70	zanardi	\N	\N	Alessandro	Zanardi	1966-10-23	Italian	http://en.wikipedia.org/wiki/Alex_Zanardi
71	damon_hill	\N	\N	Damon	Hill	1960-09-17	British	http://en.wikipedia.org/wiki/Damon_Hill
72	sarrazin	\N	\N	Stéphane	Sarrazin	1975-11-02	French	http://en.wikipedia.org/wiki/St%C3%A9phane_Sarrazin
73	rosset	\N	\N	Ricardo	Rosset	1968-07-27	Brazilian	http://en.wikipedia.org/wiki/Ricardo_Rosset
74	tuero	\N	\N	Esteban	Tuero	1978-04-22	Argentine	http://en.wikipedia.org/wiki/Esteban_Tuero
75	nakano	\N	\N	Shinji	Nakano	1971-04-01	Japanese	http://en.wikipedia.org/wiki/Shinji_Nakano
76	magnussen	\N	MAG	Jan	Magnussen	1973-07-04	Danish	http://en.wikipedia.org/wiki/Jan_Magnussen
77	berger	\N	\N	Gerhard	Berger	1959-08-27	Austrian	http://en.wikipedia.org/wiki/Gerhard_Berger
78	larini	\N	\N	Nicola	Larini	1964-03-19	Italian	http://en.wikipedia.org/wiki/Nicola_Larini
79	katayama	\N	\N	Ukyo	Katayama	1963-05-29	Japanese	http://en.wikipedia.org/wiki/Ukyo_Katayama
80	sospiri	\N	\N	Vincenzo	Sospiri	1966-10-07	Italian	http://en.wikipedia.org/wiki/Vincenzo_Sospiri
81	morbidelli	\N	\N	Gianni	Morbidelli	1968-01-13	Italian	http://en.wikipedia.org/wiki/Gianni_Morbidelli
82	fontana	\N	\N	Norberto	Fontana	1975-01-20	Argentine	http://en.wikipedia.org/wiki/Norberto_Fontana
83	lamy	\N	\N	Pedro	Lamy	1972-03-20	Portuguese	http://en.wikipedia.org/wiki/Pedro_Lamy
84	brundle	\N	\N	Martin	Brundle	1959-06-01	British	http://en.wikipedia.org/wiki/Martin_Brundle
85	montermini	\N	\N	Andrea	Montermini	1964-05-30	Italian	http://en.wikipedia.org/wiki/Andrea_Montermini
86	lavaggi	\N	\N	Giovanni	Lavaggi	1958-02-18	Italian	http://en.wikipedia.org/wiki/Giovanni_Lavaggi
87	blundell	\N	\N	Mark	Blundell	1966-04-08	British	http://en.wikipedia.org/wiki/Mark_Blundell
88	suzuki	\N	\N	Aguri	Suzuki	1960-09-08	Japanese	http://en.wikipedia.org/wiki/Aguri_Suzuki
89	inoue	\N	\N	Taki	Inoue	1963-09-05	Japanese	http://en.wikipedia.org/wiki/Taki_Inoue
90	moreno	\N	\N	Roberto	Moreno	1959-02-11	Brazilian	http://en.wikipedia.org/wiki/Roberto_Moreno
91	wendlinger	\N	\N	Karl	Wendlinger	1968-12-20	Austrian	http://en.wikipedia.org/wiki/Karl_Wendlinger
92	gachot	\N	\N	Bertrand	Gachot	1962-12-23	Belgian	http://en.wikipedia.org/wiki/Bertrand_Gachot
93	schiattarella	\N	\N	Domenico	Schiattarella	1967-11-17	Italian	http://en.wikipedia.org/wiki/Domenico_Schiattarella
94	martini	\N	\N	Pierluigi	Martini	1961-04-23	Italian	http://en.wikipedia.org/wiki/Pierluigi_Martini
95	mansell	\N	\N	Nigel	Mansell	1953-08-08	British	http://en.wikipedia.org/wiki/Nigel_Mansell
96	boullion	\N	\N	Jean-Christophe	Boullion	1969-12-27	French	http://en.wikipedia.org/wiki/Jean-Christophe_Boullion
97	papis	\N	\N	Massimiliano	Papis	1969-10-03	Italian	http://en.wikipedia.org/wiki/Massimiliano_Papis
98	deletraz	\N	\N	Jean-Denis	Délétraz	1963-10-01	Swiss	http://en.wikipedia.org/wiki/Jean-Denis_Deletraz
99	tarquini	\N	\N	Gabriele	Tarquini	1962-03-02	Italian	http://en.wikipedia.org/wiki/Gabriele_Tarquini
100	comas	\N	\N	Érik	Comas	1963-09-28	French	http://en.wikipedia.org/wiki/%C3%89rik_Comas
101	brabham	\N	\N	David	Brabham	1965-09-05	Australian	http://en.wikipedia.org/wiki/David_Brabham
102	senna	\N	\N	Ayrton	Senna	1960-03-21	Brazilian	http://en.wikipedia.org/wiki/Ayrton_Senna
103	bernard	\N	\N	Éric	Bernard	1964-08-24	French	http://en.wikipedia.org/wiki/%C3%89ric_Bernard
104	fittipaldi	\N	\N	Christian	Fittipaldi	1971-01-18	Brazilian	http://en.wikipedia.org/wiki/Christian_Fittipaldi
105	alboreto	\N	\N	Michele	Alboreto	1956-12-23	Italian	http://en.wikipedia.org/wiki/Michele_Alboreto
106	beretta	\N	\N	Olivier	Beretta	1969-11-23	Monegasque	http://en.wikipedia.org/wiki/Olivier_Beretta
107	ratzenberger	\N	\N	Roland	Ratzenberger	1960-07-04	Austrian	http://en.wikipedia.org/wiki/Roland_Ratzenberger
108	belmondo	\N	\N	Paul	Belmondo	1963-04-23	French	http://en.wikipedia.org/wiki/Paul_Belmondo
109	lehto	\N	\N	Jyrki	Järvilehto	1966-01-31	Finnish	http://en.wikipedia.org/wiki/Jyrki_J%C3%A4rvilehto
110	cesaris	\N	\N	Andrea	de Cesaris	1959-05-31	Italian	http://en.wikipedia.org/wiki/Andrea_de_Cesaris
111	gounon	\N	\N	Jean-Marc	Gounon	1963-01-01	French	http://en.wikipedia.org/wiki/Jean-Marc_Gounon
112	alliot	\N	\N	Philippe	Alliot	1954-07-27	French	http://en.wikipedia.org/wiki/Philippe_Alliot
113	adams	\N	\N	Philippe	Adams	1969-11-19	Belgian	http://en.wikipedia.org/wiki/Philippe_Adams
114	dalmas	\N	\N	Yannick	Dalmas	1961-07-28	French	http://en.wikipedia.org/wiki/Yannick_Dalmas
115	noda	\N	\N	Hideki	Noda	1969-03-07	Japanese	http://en.wikipedia.org/wiki/Hideki_Noda
116	lagorce	\N	\N	Franck	Lagorce	1968-09-01	French	http://en.wikipedia.org/wiki/Franck_Lagorce
117	prost	\N	\N	Alain	Prost	1955-02-24	French	http://en.wikipedia.org/wiki/Alain_Prost
118	warwick	\N	\N	Derek	Warwick	1954-08-27	British	http://en.wikipedia.org/wiki/Derek_Warwick
119	patrese	\N	\N	Riccardo	Patrese	1954-04-17	Italian	http://en.wikipedia.org/wiki/Riccardo_Patrese
120	barbazza	\N	\N	Fabrizio	Barbazza	1963-04-02	Italian	http://en.wikipedia.org/wiki/Fabrizio_Barbazza
121	andretti	\N	\N	Michael	Andretti	1962-10-05	American	http://en.wikipedia.org/wiki/Michael_Andretti
122	capelli	\N	\N	Ivan	Capelli	1963-05-24	Italian	http://en.wikipedia.org/wiki/Ivan_Capelli
123	boutsen	\N	\N	Thierry	Boutsen	1957-07-13	Belgian	http://en.wikipedia.org/wiki/Thierry_Boutsen
124	apicella	\N	\N	Marco	Apicella	1965-10-07	Italian	http://en.wikipedia.org/wiki/Marco_Apicella
125	naspetti	\N	\N	Emanuele	Naspetti	1968-02-24	Italian	http://en.wikipedia.org/wiki/Emanuele_Naspetti
126	toshio_suzuki	\N	\N	Toshio	Suzuki	1955-03-10	Japanese	http://en.wikipedia.org/wiki/Toshio_Suzuki_(driver)
127	gugelmin	\N	\N	Maurício	Gugelmin	1963-04-20	Brazilian	http://en.wikipedia.org/wiki/Maur%C3%ADcio_Gugelmin
128	poele	\N	\N	Eric	van de Poele	1961-09-30	Belgian	http://en.wikipedia.org/wiki/Eric_van_de_Poele
129	grouillard	\N	\N	Olivier	Grouillard	1958-09-02	French	http://en.wikipedia.org/wiki/Olivier_Grouillard
130	chiesa	\N	\N	Andrea	Chiesa	1964-05-06	Swiss	http://en.wikipedia.org/wiki/Andrea_Chiesa
131	modena	\N	\N	Stefano	Modena	1963-05-12	Italian	http://en.wikipedia.org/wiki/Stefano_Modena
132	amati	\N	\N	Giovanna	Amati	1959-07-20	Italian	http://en.wikipedia.org/wiki/Giovanna_Amati
133	caffi	\N	\N	Alex	Caffi	1964-03-18	Italian	http://en.wikipedia.org/wiki/Alex_Caffi
134	bertaggia	\N	\N	Enrico	Bertaggia	1964-09-19	Italian	http://en.wikipedia.org/wiki/Enrico_Bertaggia
135	mccarthy	\N	\N	Perry	McCarthy	1961-03-03	British	http://en.wikipedia.org/wiki/Perry_McCarthy
136	lammers	\N	\N	Jan	Lammers	1956-06-02	Dutch	http://en.wikipedia.org/wiki/Jan_Lammers
137	piquet	\N	\N	Nelson	Piquet	1952-08-17	Brazilian	http://en.wikipedia.org/wiki/Nelson_Piquet
138	satoru_nakajima	\N	\N	Satoru	Nakajima	1953-02-23	Japanese	http://en.wikipedia.org/wiki/Satoru_Nakajima
139	pirro	\N	\N	Emanuele	Pirro	1962-01-12	Italian	http://en.wikipedia.org/wiki/Emanuele_Pirro
140	johansson	\N	\N	Stefan	Johansson	1956-09-08	Swedish	http://en.wikipedia.org/wiki/Stefan_Johansson
141	bailey	\N	\N	Julian	Bailey	1961-10-09	British	http://en.wikipedia.org/wiki/Julian_Bailey
142	chaves	\N	\N	Pedro	Chaves	1965-02-27	Portuguese	http://en.wikipedia.org/wiki/Pedro_Chaves
143	bartels	\N	\N	Michael	Bartels	1968-03-08	German	http://en.wikipedia.org/wiki/Michael_Bartels
144	hattori	\N	\N	Naoki	Hattori	1966-06-13	Japanese	http://en.wikipedia.org/wiki/Naoki_Hattori
145	nannini	\N	\N	Alessandro	Nannini	1959-07-07	Italian	http://en.wikipedia.org/wiki/Alessandro_Nannini
146	schneider	\N	\N	Bernd	Schneider	1964-07-20	German	http://en.wikipedia.org/wiki/Bernd_Schneider_(racecar_driver)
147	barilla	\N	\N	Paolo	Barilla	1961-04-20	Italian	http://en.wikipedia.org/wiki/Paolo_Barilla
148	foitek	\N	\N	Gregor	Foitek	1965-03-27	Swiss	http://en.wikipedia.org/wiki/Gregor_Foitek
149	langes	\N	\N	Claudio	Langes	1960-07-20	Italian	http://en.wikipedia.org/wiki/Claudio_Langes
150	gary_brabham	\N	\N	Gary	Brabham	1961-03-29	Australian	http://en.wikipedia.org/wiki/Gary_Brabham
151	donnelly	\N	\N	Martin	Donnelly	1964-03-26	British	http://en.wikipedia.org/wiki/Martin_Donnelly_(racing_driver)
152	giacomelli	\N	\N	Bruno	Giacomelli	1952-09-10	Italian	http://en.wikipedia.org/wiki/Bruno_Giacomelli
153	alguersuari	\N	ALG	Jaime	Alguersuari	1990-03-23	Spanish	http://en.wikipedia.org/wiki/Jaime_Alguersuari
154	grosjean	8	GRO	Romain	Grosjean	1986-04-17	French	http://en.wikipedia.org/wiki/Romain_Grosjean
155	kobayashi	10	KOB	Kamui	Kobayashi	1986-09-13	Japanese	http://en.wikipedia.org/wiki/Kamui_Kobayashi
156	palmer	\N	\N	Jonathan	Palmer	1956-11-07	British	http://en.wikipedia.org/wiki/Jonathan_Palmer
157	danner	\N	\N	Christian	Danner	1958-04-04	German	http://en.wikipedia.org/wiki/Christian_Danner
158	cheever	\N	\N	Eddie	Cheever	1958-01-10	American	http://en.wikipedia.org/wiki/Eddie_Cheever
159	sala	\N	\N	Luis	Pérez-Sala	1959-05-15	Spanish	http://en.wikipedia.org/wiki/Luis_Perez-Sala
160	ghinzani	\N	\N	Piercarlo	Ghinzani	1952-01-16	Italian	http://en.wikipedia.org/wiki/Piercarlo_Ghinzani
161	weidler	\N	\N	Volker	Weidler	1962-03-18	German	http://en.wikipedia.org/wiki/Volker_Weidler
162	raphanel	\N	\N	Pierre-Henri	Raphanel	1961-05-27	French	http://en.wikipedia.org/wiki/Pierre-Henri_Raphanel
163	arnoux	\N	\N	René	Arnoux	1948-07-04	French	http://en.wikipedia.org/wiki/Ren%C3%A9_Arnoux
164	joachim_winkelhock	\N	\N	Joachim	Winkelhock	1960-10-24	German	http://en.wikipedia.org/wiki/Joachim_Winkelhock
165	larrauri	\N	\N	Oscar	Larrauri	1954-08-19	Argentine	http://en.wikipedia.org/wiki/Oscar_Larrauri
166	streiff	\N	\N	Philippe	Streiff	1955-06-26	French	http://en.wikipedia.org/wiki/Philippe_Streiff
167	campos	\N	\N	Adrián	Campos	1960-06-17	Spanish	http://en.wikipedia.org/wiki/Adri%C3%A1n_Campos
168	schlesser	\N	\N	Jean-Louis	Schlesser	1948-09-12	French	http://en.wikipedia.org/wiki/Jean-Louis_Schlesser
169	fabre	\N	\N	Pascal	Fabre	1960-01-09	French	http://en.wikipedia.org/wiki/Pascal_Fabre
170	fabi	\N	\N	Teo	Fabi	1955-03-09	Italian	http://en.wikipedia.org/wiki/Teo_Fabi
171	forini	\N	\N	Franco	Forini	1958-09-22	Swiss	http://en.wikipedia.org/wiki/Franco_Forini
172	laffite	\N	\N	Jacques	Laffite	1943-11-21	French	http://en.wikipedia.org/wiki/Jacques_Laffite
173	angelis	\N	\N	Elio	de Angelis	1958-03-26	Italian	http://en.wikipedia.org/wiki/Elio_de_Angelis
174	dumfries	\N	\N	Johnny	Dumfries	1958-04-26	British	http://en.wikipedia.org/wiki/Johnny_Dumfries
175	tambay	\N	\N	Patrick	Tambay	1949-06-25	French	http://en.wikipedia.org/wiki/Patrick_Tambay
176	surer	\N	\N	Marc	Surer	1951-09-18	Swiss	http://en.wikipedia.org/wiki/Marc_Surer
177	keke_rosberg	\N	\N	Keke	Rosberg	1948-12-06	Finnish	http://en.wikipedia.org/wiki/Keke_Rosberg
178	jones	\N	\N	Alan	Jones	1946-11-02	Australian	http://en.wikipedia.org/wiki/Alan_Jones_(Formula_1)
179	rothengatter	\N	\N	Huub	Rothengatter	1954-10-08	Dutch	http://en.wikipedia.org/wiki/Huub_Rothengatter
180	berg	\N	\N	Allen	Berg	1961-08-01	Canadian	http://en.wikipedia.org/wiki/Allen_Berg
181	manfred_winkelhock	\N	\N	Manfred	Winkelhock	1951-10-06	German	http://en.wikipedia.org/wiki/Manfred_Winkelhock
182	lauda	\N	\N	Niki	Lauda	1949-02-22	Austrian	http://en.wikipedia.org/wiki/Niki_Lauda
183	hesnault	\N	\N	François	Hesnault	1956-12-30	French	http://en.wikipedia.org/wiki/Fran%C3%A7ois_Hesnault
184	baldi	\N	\N	Mauro	Baldi	1954-01-31	Italian	http://en.wikipedia.org/wiki/Mauro_Baldi
185	bellof	\N	\N	Stefan	Bellof	1957-11-20	German	http://en.wikipedia.org/wiki/Stefan_Bellof
186	acheson	\N	\N	Kenny	Acheson	1957-11-27	British	http://en.wikipedia.org/wiki/Kenny_Acheson
187	watson	\N	\N	John	Watson	1946-05-04	British	http://en.wikipedia.org/wiki/John_Watson_(racing_driver)
188	cecotto	\N	\N	Johnny	Cecotto	1956-01-25	Venezuelan	http://en.wikipedia.org/wiki/Johnny_Cecotto
189	gartner	\N	\N	Jo	Gartner	1954-01-24	Austrian	http://en.wikipedia.org/wiki/Jo_Gartner
190	corrado_fabi	\N	\N	Corrado	Fabi	1961-04-12	Italian	http://en.wikipedia.org/wiki/Corrado_Fabi
191	thackwell	\N	\N	Mike	Thackwell	1961-03-30	New Zealander	http://en.wikipedia.org/wiki/Mike_Thackwell
192	serra	\N	\N	Chico	Serra	1957-02-03	Brazilian	http://en.wikipedia.org/wiki/Chico_Serra
193	sullivan	\N	\N	Danny	Sullivan	1950-03-09	American	http://en.wikipedia.org/wiki/Danny_Sullivan
194	salazar	\N	\N	Eliseo	Salazar	1954-11-14	Chilean	http://en.wikipedia.org/wiki/Eliseo_Salazar
195	guerrero	\N	\N	Roberto	Guerrero	1958-11-16	Colombian	http://en.wikipedia.org/wiki/Roberto_Guerrero
196	boesel	\N	\N	Raul	Boesel	1957-12-04	Brazilian	http://en.wikipedia.org/wiki/Raul_Boesel
197	jarier	\N	\N	Jean-Pierre	Jarier	1946-07-10	French	http://en.wikipedia.org/wiki/Jean-Pierre_Jarier
198	villeneuve_sr	\N	\N	Jacques	Villeneuve Sr.	1953-11-04	Canadian	http://en.wikipedia.org/wiki/Jacques_Villeneuve_(elder)
199	reutemann	\N	\N	Carlos	Reutemann	1942-04-12	Argentine	http://en.wikipedia.org/wiki/Carlos_Reutemann
200	mass	\N	\N	Jochen	Mass	1946-09-30	German	http://en.wikipedia.org/wiki/Jochen_Mass
201	borgudd	\N	\N	Slim	Borgudd	1946-11-25	Swedish	http://en.wikipedia.org/wiki/Slim_Borgudd
202	pironi	\N	\N	Didier	Pironi	1952-03-26	French	http://en.wikipedia.org/wiki/Didier_Pironi
203	gilles_villeneuve	\N	\N	Gilles	Villeneuve	1950-01-18	Canadian	http://en.wikipedia.org/wiki/Gilles_Villeneuve
204	paletti	\N	\N	Riccardo	Paletti	1958-06-15	Italian	http://en.wikipedia.org/wiki/Riccardo_Paletti
205	henton	\N	\N	Brian	Henton	1946-09-19	British	http://en.wikipedia.org/wiki/Brian_Henton
206	daly	\N	\N	Derek	Daly	1953-03-11	Irish	http://en.wikipedia.org/wiki/Derek_Daly
207	mario_andretti	\N	\N	Mario	Andretti	1940-02-28	American	http://en.wikipedia.org/wiki/Mario_Andretti
208	villota	\N	\N	Emilio	de Villota	1946-07-26	Spanish	http://en.wikipedia.org/wiki/Emilio_de_Villota
209	lees	\N	\N	Geoff	Lees	1951-05-01	British	http://en.wikipedia.org/wiki/Geoff_Lees
210	byrne	\N	\N	Tommy	Byrne	1958-05-06	Irish	http://en.wikipedia.org/wiki/Tommy_Byrne_%28racing_driver%29
211	keegan	\N	\N	Rupert	Keegan	1955-02-26	British	http://en.wikipedia.org/wiki/Rupert_Keegan
212	rebaque	\N	\N	Hector	Rebaque	1956-02-05	Mexican	http://en.wikipedia.org/wiki/Hector_Rebaque
213	gabbiani	\N	\N	Beppe	Gabbiani	1957-01-02	Italian	http://en.wikipedia.org/wiki/Beppe_Gabbiani
214	cogan	\N	\N	Kevin	Cogan	1956-03-31	American	http://en.wikipedia.org/wiki/Kevin_Cogan
215	guerra	\N	\N	Miguel Ángel	Guerra	1953-08-31	Argentine	http://en.wikipedia.org/wiki/Miguel_Angel_Guerra
216	stohr	\N	\N	Siegfried	Stohr	1952-10-10	Italian	http://en.wikipedia.org/wiki/Siegfried_Stohr
217	zunino	\N	\N	Ricardo	Zunino	1949-04-13	Argentine	http://en.wikipedia.org/wiki/Ricardo_Zunino
218	londono	\N	\N	Ricardo	Londoño	1949-08-08	Colombian	http://en.wikipedia.org/wiki/Ricardo_Londo%C3%B1o
219	jabouille	\N	\N	Jean-Pierre	Jabouille	1942-10-01	French	http://en.wikipedia.org/wiki/Jean-Pierre_Jabouille
220	francia	\N	\N	Giorgio	Francia	1947-11-08	Italian	http://en.wikipedia.org/wiki/Giorgio_Francia
221	depailler	\N	\N	Patrick	Depailler	1944-08-09	French	http://en.wikipedia.org/wiki/Patrick_Depailler
222	scheckter	\N	\N	Jody	Scheckter	1950-01-29	South African	http://en.wikipedia.org/wiki/Jody_Scheckter
223	regazzoni	\N	\N	Clay	Regazzoni	1939-09-05	Swiss	http://en.wikipedia.org/wiki/Clay_Regazzoni
224	emerson_fittipaldi	\N	\N	Emerson	Fittipaldi	1946-12-12	Brazilian	http://en.wikipedia.org/wiki/Emerson_Fittipaldi
225	kennedy	\N	\N	Dave	Kennedy	1953-01-15	Irish	http://en.wikipedia.org/wiki/David_Kennedy_(racing_driver)
226	south	\N	\N	Stephen	South	1952-02-19	British	http://en.wikipedia.org/wiki/Stephen_South
227	needell	\N	\N	Tiff	Needell	1951-10-29	British	http://en.wikipedia.org/wiki/Tiff_Needell
228	desire_wilson	\N	\N	Desiré	Wilson	1953-11-26	South African	http://en.wikipedia.org/wiki/Desir%C3%A9_Wilson
229	ertl	\N	\N	Harald	Ertl	1948-08-31	Austrian	http://en.wikipedia.org/wiki/Harald_Ertl
230	brambilla	\N	\N	Vittorio	Brambilla	1937-11-11	Italian	http://en.wikipedia.org/wiki/Vittorio_Brambilla
231	hunt	\N	\N	James	Hunt	1947-08-29	British	http://en.wikipedia.org/wiki/James_Hunt
232	merzario	\N	\N	Arturo	Merzario	1943-03-11	Italian	http://en.wikipedia.org/wiki/Arturo_Merzario
233	stuck	\N	\N	Hans-Joachim	Stuck	1951-01-01	German	http://en.wikipedia.org/wiki/Hans_Joachim_Stuck
234	brancatelli	\N	\N	Gianfranco	Brancatelli	1950-01-18	Italian	http://en.wikipedia.org/wiki/Gianfranco_Brancatelli
235	ickx	\N	\N	Jacky	Ickx	1945-01-01	Belgian	http://en.wikipedia.org/wiki/Jacky_Ickx
236	gaillard	\N	\N	Patrick	Gaillard	1952-02-12	French	http://en.wikipedia.org/wiki/Patrick_Gaillard
237	ribeiro	\N	\N	Alex	Ribeiro	1948-11-07	Brazilian	http://en.wikipedia.org/wiki/Alex_Ribeiro
238	peterson	\N	\N	Ronnie	Peterson	1944-02-14	Swedish	http://en.wikipedia.org/wiki/Ronnie_Peterson
239	lunger	\N	\N	Brett	Lunger	1945-11-14	American	http://en.wikipedia.org/wiki/Brett_Lunger
240	ongais	\N	\N	Danny	Ongais	1942-05-21	American	http://en.wikipedia.org/wiki/Danny_Ongais
241	leoni	\N	\N	Lamberto	Leoni	1953-05-24	Italian	http://en.wikipedia.org/wiki/Lamberto_Leoni
242	galica	\N	\N	Divina	Galica	1944-08-13	British	http://en.wikipedia.org/wiki/Divina_Galica
243	stommelen	\N	\N	Rolf	Stommelen	1943-07-11	German	http://en.wikipedia.org/wiki/Rolf_Stommelen
244	colombo	\N	\N	Alberto	Colombo	1946-02-23	Italian	http://en.wikipedia.org/wiki/Alberto_Colombo
245	trimmer	\N	\N	Tony	Trimmer	1943-01-24	British	http://en.wikipedia.org/wiki/Tony_Trimmer
246	binder	\N	\N	Hans	Binder	1948-06-12	Austrian	http://en.wikipedia.org/wiki/Hans_Binder
247	bleekemolen	\N	\N	Michael	Bleekemolen	1949-10-02	Dutch	http://en.wikipedia.org/wiki/Michael_Bleekemolen
248	gimax	\N	\N	Carlo	Franchi	1938-01-01	Italian	http://en.wikipedia.org/wiki/Gimax
249	rahal	\N	\N	Bobby	Rahal	1953-01-10	American	http://en.wikipedia.org/wiki/Bobby_Rahal
250	pace	\N	\N	Carlos	Pace	1944-10-06	Brazilian	http://en.wikipedia.org/wiki/Carlos_Pace
251	ian_scheckter	\N	\N	Ian	Scheckter	1947-08-22	South African	http://en.wikipedia.org/wiki/Ian_Scheckter
252	pryce	\N	\N	Tom	Pryce	1949-06-11	British	http://en.wikipedia.org/wiki/Tom_Pryce
253	hoffmann	\N	\N	Ingo	Hoffmann	1953-02-28	Brazilian	http://en.wikipedia.org/wiki/Ingo_Hoffmann
254	zorzi	\N	\N	Renzo	Zorzi	1946-12-12	Italian	http://en.wikipedia.org/wiki/Renzo_Zorzi
255	nilsson	\N	\N	Gunnar	Nilsson	1948-11-20	Swedish	http://en.wikipedia.org/wiki/Gunnar_Nilsson
256	perkins	\N	\N	Larry	Perkins	1950-03-18	Australian	http://en.wikipedia.org/wiki/Larry_Perkins
257	hayje	\N	\N	Boy	Lunger	1949-05-03	Dutch	http://en.wikipedia.org/wiki/Boy_Hayje
258	neve	\N	\N	Patrick	Nève	1949-10-13	Belgian	http://en.wikipedia.org/wiki/Patrick_Neve
259	purley	\N	\N	David	Purley	1945-01-26	British	http://en.wikipedia.org/wiki/David_Purley
260	andersson	\N	\N	Conny	Andersson	1939-12-28	Swedish	http://en.wikipedia.org/wiki/Conny_Andersson_(racing_driver)
261	dryver	\N	\N	Bernard	de Dryver	1952-09-19	Belgian	http://en.wikipedia.org/wiki/Bernard_de_Dryver
262	oliver	\N	\N	Jackie	Oliver	1942-08-14	British	http://en.wikipedia.org/wiki/Jackie_Oliver
263	kozarowitzky	\N	\N	Mikko	Kozarowitzky	1948-05-17	Finnish	http://en.wikipedia.org/wiki/Mikko_Kozarowitzky
264	sutcliffe	\N	\N	Andy	Sutcliffe	1947-05-09	British	http://en.wikipedia.org/wiki/Andy_Sutcliffe
265	edwards	\N	\N	Guy	Edwards	1942-12-30	British	http://en.wikipedia.org/wiki/Guy_Edwards
266	mcguire	\N	\N	Brian	McGuire	1945-12-13	Australian	http://en.wikipedia.org/wiki/Brian_McGuire
267	schuppan	\N	\N	Vern	Schuppan	1943-03-19	Australian	http://en.wikipedia.org/wiki/Vern_Schuppan
268	heyer	\N	\N	Hans	Heyer	1943-03-16	German	http://en.wikipedia.org/wiki/Hans_Heyer
269	pilette	\N	\N	Teddy	Pilette	1942-07-26	Belgian	http://en.wikipedia.org/wiki/Teddy_Pilette
270	ashley	\N	\N	Ian	Ashley	1947-10-26	British	http://en.wikipedia.org/wiki/Ian_Ashley
271	kessel	\N	\N	Loris	Kessel	1950-04-01	Swiss	http://en.wikipedia.org/wiki/Loris_Kessel
272	takahashi	\N	\N	Kunimitsu	Takahashi	1940-01-29	Japanese	http://en.wikipedia.org/wiki/Kunimitsu_Takahashi
273	hoshino	\N	\N	Kazuyoshi	Hoshino	1947-07-01	Japanese	http://en.wikipedia.org/wiki/Kazuyoshi_Hoshino
274	takahara	\N	\N	Noritake	Takahara	1951-06-06	Japanese	http://en.wikipedia.org/wiki/Noritake_Takahara
275	lombardi	\N	\N	Lella	Lombardi	1941-03-26	Italian	http://en.wikipedia.org/wiki/Lella_Lombardi
276	evans	\N	\N	Bob	Evans	1947-06-11	British	http://en.wikipedia.org/wiki/Bob_Evans_(race_driver)
277	leclere	\N	\N	Michel	Leclère	1946-03-18	French	http://en.wikipedia.org/wiki/Michel_Lecl%C3%A8re
278	amon	\N	\N	Chris	Amon	1943-07-20	New Zealander	http://en.wikipedia.org/wiki/Chris_Amon
279	zapico	\N	\N	Emilio	Zapico	1944-05-27	Spanish	http://en.wikipedia.org/wiki/Emilio_Zapico
280	pescarolo	\N	\N	Henri	Pescarolo	1942-09-25	French	http://en.wikipedia.org/wiki/Henri_Pescarolo
281	nelleman	\N	\N	Jac	Nelleman	1944-04-19	Danish	http://en.wikipedia.org/wiki/Jac_Nelleman
282	magee	\N	\N	Damien	Magee	1945-11-17	British	http://en.wikipedia.org/wiki/Damien_Magee
283	wilds	\N	\N	Mike	Wilds	1946-01-07	British	http://en.wikipedia.org/wiki/Mike_Wilds
284	pesenti_rossi	\N	\N	Alessandro	Pesenti-Rossi	1942-08-31	Italian	http://en.wikipedia.org/wiki/Alessandro_Pesenti-Rossi
285	stuppacher	\N	\N	Otto	Stuppacher	1947-03-03	Austrian	http://en.wikipedia.org/wiki/Otto_Stuppacher
286	brown	\N	\N	Warwick	Brown	1949-12-24	Australian	http://en.wikipedia.org/wiki/Warwick_Brown
287	hasemi	\N	\N	Masahiro	Hasemi	1945-11-13	Japanese	http://en.wikipedia.org/wiki/Masahiro_Hasemi
288	donohue	\N	\N	Mark	Donohue	1937-03-18	American	http://en.wikipedia.org/wiki/Mark_Donohue
289	hill	\N	\N	Graham	Hill	1929-02-15	British	http://en.wikipedia.org/wiki/Graham_Hill
290	wilson_fittipaldi	\N	\N	Wilson	Fittipaldi	1943-12-25	Brazilian	http://en.wikipedia.org/wiki/Wilson_Fittipaldi
291	tunmer	\N	\N	Guy	Tunmer	1948-12-01	South African	http://en.wikipedia.org/wiki/Guy_Tunmer
292	keizan	\N	\N	Eddie	Keizan	1944-09-12	South African	http://en.wikipedia.org/wiki/Eddie_Keizan
293	charlton	\N	\N	Dave	Charlton	1936-10-27	South African	http://en.wikipedia.org/wiki/Dave_Charlton
294	brise	\N	\N	Tony	Brise	1952-03-28	British	http://en.wikipedia.org/wiki/Tony_Brise
295	wunderink	\N	\N	Roelof	Wunderink	1948-12-12	Dutch	http://en.wikipedia.org/wiki/Roelof_Wunderink
296	migault	\N	\N	François	Migault	1944-12-04	French	http://en.wikipedia.org/wiki/Fran%C3%A7ois_Migault
297	palm	\N	\N	Torsten	Palm	1947-07-23	Swedish	http://en.wikipedia.org/wiki/Torsten_Palm
298	lennep	\N	\N	Gijs	van Lennep	1942-03-16	Dutch	http://en.wikipedia.org/wiki/Gijs_Van_Lennep
299	fushida	\N	\N	Hiroshi	Fushida	1946-03-10	Japanese	http://en.wikipedia.org/wiki/Hiroshi_Fushida
300	nicholson	\N	\N	John	Nicholson	1941-10-06	New Zealander	http://en.wikipedia.org/wiki/John_Nicholson_(racing_driver)
301	morgan	\N	\N	Dave	Morgan	1944-08-07	British	http://en.wikipedia.org/wiki/Dave_Morgan_(racing_driver)
302	crawford	\N	\N	Jim	Crawford	1948-02-13	British	http://en.wikipedia.org/wiki/Jim_Crawford_(driver)
303	vonlanthen	\N	\N	Jo	Vonlanthen	1942-05-31	Swiss	http://en.wikipedia.org/wiki/Jo_Vonlanthen
304	hulme	\N	\N	Denny	Hulme	1936-06-18	New Zealander	http://en.wikipedia.org/wiki/Denny_Hulme
305	hailwood	\N	\N	Mike	Hailwood	1940-04-02	British	http://en.wikipedia.org/wiki/Mike_Hailwood
306	beltoise	\N	\N	Jean-Pierre	Beltoise	1937-04-26	French	http://en.wikipedia.org/wiki/Jean-Pierre_Beltoise
307	ganley	\N	\N	Howden	Ganley	1941-12-24	New Zealander	http://en.wikipedia.org/wiki/Howden_Ganley
308	robarts	\N	\N	Richard	Robarts	1944-09-22	British	http://en.wikipedia.org/wiki/Richard_Robarts
309	revson	\N	\N	Peter	Revson	1939-02-27	American	http://en.wikipedia.org/wiki/Peter_Revson
310	driver	\N	\N	Paddy	Driver	1934-05-13	South African	http://en.wikipedia.org/wiki/Paddy_Driver
311	belso	\N	\N	Tom	Belsø	1942-08-27	Danish	http://en.wikipedia.org/wiki/Tom_Bels%C3%B8
312	redman	\N	\N	Brian	Redman	1937-03-09	British	http://en.wikipedia.org/wiki/Brian_Redman
313	opel	\N	\N	Rikky	von Opel	1947-10-14	Liechtensteiner	http://en.wikipedia.org/wiki/Rikky_von_Opel
314	schenken	\N	\N	Tim	Schenken	1943-09-26	Australian	http://en.wikipedia.org/wiki/Tim_Schenken
315	larrousse	\N	\N	Gérard	Larrousse	1940-05-23	French	http://en.wikipedia.org/wiki/G%C3%A9rard_Larrousse
316	kinnunen	\N	\N	Leo	Kinnunen	1943-08-05	Finnish	http://en.wikipedia.org/wiki/Leo_Kinnunen
317	wisell	\N	\N	Reine	Wisell	1941-09-30	Swedish	http://en.wikipedia.org/wiki/Reine_Wisell
318	roos	\N	\N	Bertil	Roos	1943-10-12	Swedish	http://en.wikipedia.org/wiki/Bertil_Roos
319	dolhem	\N	\N	José	Dolhem	1944-04-26	French	http://en.wikipedia.org/wiki/Jos%C3%A9_Dolhem
320	gethin	\N	\N	Peter	Gethin	1940-02-21	British	http://en.wikipedia.org/wiki/Peter_Gethin
321	bell	\N	\N	Derek	Bell	1941-10-31	British	http://en.wikipedia.org/wiki/Derek_Bell_(auto_racer)
322	hobbs	\N	\N	David	Hobbs	1939-06-09	British	http://en.wikipedia.org/wiki/David_Hobbs_(racing_driver)
323	quester	\N	\N	Dieter	Quester	1939-05-30	Austrian	http://en.wikipedia.org/wiki/Dieter_Quester
324	koinigg	\N	\N	Helmuth	Koinigg	1948-11-03	Austrian	http://en.wikipedia.org/wiki/Helmuth_Koinigg
325	facetti	\N	\N	Carlo	Facetti	1935-06-26	Italian	http://en.wikipedia.org/wiki/Carlo_Facetti
326	wietzes	\N	\N	Eppie	Wietzes	1938-05-28	Canadian	http://en.wikipedia.org/wiki/Eppie_Wietzes
327	cevert	\N	\N	François	Cevert	1944-02-25	French	http://en.wikipedia.org/wiki/Fran%C3%A7ois_Cevert
328	stewart	\N	\N	Jackie	Stewart	1939-06-11	British	http://en.wikipedia.org/wiki/Jackie_Stewart
329	beuttler	\N	\N	Mike	Beuttler	1940-04-13	British	http://en.wikipedia.org/wiki/Mike_Beuttler
330	galli	\N	\N	Nanni	Galli	1940-10-02	Italian	http://en.wikipedia.org/wiki/Nanni_Galli
331	bueno	\N	\N	Luiz	Bueno	1937-01-16	Brazilian	http://en.wikipedia.org/wiki/Luiz_Bueno
332	follmer	\N	\N	George	Follmer	1934-01-27	American	http://en.wikipedia.org/wiki/George_Follmer
333	adamich	\N	\N	Andrea	de Adamich	1941-10-03	Italian	http://en.wikipedia.org/wiki/Andrea_de_Adamich
334	pretorius	\N	\N	Jackie	Pretorius	1934-11-22	South African	http://en.wikipedia.org/wiki/Jackie_Pretorius
335	williamson	\N	\N	Roger	Williamson	1948-02-02	British	http://en.wikipedia.org/wiki/Roger_Williamson
336	mcrae	\N	\N	Graham	McRae	1940-03-05	New Zealander	http://en.wikipedia.org/wiki/Graham_McRae
337	marko	\N	\N	Helmut	Marko	1943-04-27	Austrian	http://en.wikipedia.org/wiki/Helmut_Marko
338	walker	\N	\N	David	Walker	1941-06-10	Australian	http://en.wikipedia.org/wiki/David_Walker_(racing_driver)
339	roig	\N	\N	Alex	Soler-Roig	1932-10-29	Spanish	http://en.wikipedia.org/wiki/Alex_Soler-Roig
340	love	\N	\N	John	Love	1924-12-07	Rhodesian	http://en.wikipedia.org/wiki/John_Love_(racing_driver)
341	surtees	\N	\N	John	Surtees	1934-02-11	British	http://en.wikipedia.org/wiki/John_Surtees
342	barber	\N	\N	Skip	Barber	1936-11-16	American	http://en.wikipedia.org/wiki/Skip_Barber
343	brack	\N	\N	Bill	Brack	1935-12-26	Canadian	http://en.wikipedia.org/wiki/Bill_Brack
344	posey	\N	\N	Sam	Posey	1944-05-26	American	http://en.wikipedia.org/wiki/Sam_Posey
345	rodriguez	\N	\N	Pedro	Rodríguez	1940-01-18	Mexican	http://en.wikipedia.org/wiki/Pedro_Rodr%C3%ADguez_(racing_driver)
346	siffert	\N	\N	Jo	Siffert	1936-07-07	Swiss	http://en.wikipedia.org/wiki/Jo_Siffert
347	bonnier	\N	\N	Jo	Bonnier	1930-01-31	Swedish	http://en.wikipedia.org/wiki/Joakim_Bonnier
348	mazet	\N	\N	François	Mazet	1943-02-24	French	http://en.wikipedia.org/wiki/Fran%C3%A7ois_Mazet
349	jean	\N	\N	Max	Jean	1943-07-27	French	http://en.wikipedia.org/wiki/Max_Jean
350	elford	\N	\N	Vic	Elford	1935-06-10	British	http://en.wikipedia.org/wiki/Vic_Elford
351	moser	\N	\N	Silvio	Moser	1941-04-24	Swiss	http://en.wikipedia.org/wiki/Silvio_Moser
352	eaton	\N	\N	George	Eaton	1945-11-12	Canadian	http://en.wikipedia.org/wiki/George_Eaton
353	lovely	\N	\N	Pete	Lovely	1926-04-11	American	http://en.wikipedia.org/wiki/Pete_Lovely
354	craft	\N	\N	Chris	Craft	1939-11-17	British	http://en.wikipedia.org/wiki/Chris_Craft_(racing_driver)
355	cannoc	\N	\N	John	Cannon	1933-06-21	Canadian	http://en.wikipedia.org/wiki/John_Cannon_(auto_racer)
356	jack_brabham	\N	\N	Jack	Brabham	1926-04-02	Australian	http://en.wikipedia.org/wiki/Jack_Brabham
357	miles	\N	\N	John	Miles	1943-06-14	British	http://en.wikipedia.org/wiki/John_Miles_(auto_racer)
358	rindt	\N	\N	Jochen	Rindt	1942-04-18	Austrian	http://en.wikipedia.org/wiki/Jochen_Rindt
359	gavin	\N	\N	Johnny	Servoz-Gavin	1942-01-18	French	http://en.wikipedia.org/wiki/Johnny_Servoz-Gavin
360	mclaren	\N	\N	Bruce	McLaren	1937-08-30	New Zealander	http://en.wikipedia.org/wiki/Bruce_McLaren
361	courage	\N	\N	Piers	Courage	1942-05-27	British	http://en.wikipedia.org/wiki/Piers_Courage
362	klerk	\N	\N	Peter	de Klerk	1935-03-16	South African	http://en.wikipedia.org/wiki/Peter_de_Klerk
363	giunti	\N	\N	Ignazio	Giunti	1941-08-30	Italian	http://en.wikipedia.org/wiki/Ignazio_Giunti
364	gurney	\N	\N	Dan	Gurney	1931-04-13	American	http://en.wikipedia.org/wiki/Dan_Gurney
365	hahne	\N	\N	Hubert	Hahne	1935-03-28	German	http://en.wikipedia.org/wiki/Hubert_Hahne
366	hutchison	\N	\N	Gus	Hutchison	1937-04-26	American	http://en.wikipedia.org/wiki/Gus_Hutchison
367	westbury	\N	\N	Peter	Westbury	1938-05-26	British	http://en.wikipedia.org/wiki/Peter_Westbury
368	tingle	\N	\N	Sam	Tingle	1921-08-24	Rhodesian	http://en.wikipedia.org/wiki/Sam_Tingle
369	rooyen	\N	\N	Basil	van Rooyen	1939-04-19	South African	http://en.wikipedia.org/wiki/Basil_van_Rooyen
370	attwood	\N	\N	Richard	Attwood	1940-04-04	British	http://en.wikipedia.org/wiki/Richard_Attwood
371	pease	\N	\N	Al	Pease	1921-10-15	Canadian	http://en.wikipedia.org/wiki/Al_Pease
372	cordts	\N	\N	John	Cordts	1935-07-23	Canadian	http://en.wikipedia.org/wiki/John_Cordts
373	clark	\N	\N	Jim	Clark	1936-03-04	British	http://en.wikipedia.org/wiki/Jim_Clark
374	spence	\N	\N	Mike	Spence	1936-12-30	British	http://en.wikipedia.org/wiki/Mike_Spence
375	scarfiotti	\N	\N	Ludovico	Scarfiotti	1933-10-18	Italian	http://en.wikipedia.org/wiki/Ludovico_Scarfiotti
376	bianchi	\N	BIA	Lucien	Bianchi	1934-11-10	Belgian	http://en.wikipedia.org/wiki/Lucien_Bianchi
377	jo_schlesser	\N	\N	Jo	Schlesser	1928-05-18	French	http://en.wikipedia.org/wiki/Jo_Schlesser
378	widdows	\N	\N	Robin	Widdows	1942-05-27	British	http://en.wikipedia.org/wiki/Robin_Widdows
379	ahrens	\N	\N	Kurt	Ahrens	1940-04-19	German	http://en.wikipedia.org/wiki/Kurt_Ahrens,_Jr.
380	gardner	\N	\N	Frank	Gardner	1930-10-01	Australian	http://en.wikipedia.org/wiki/Frank_Gardner_(driver)
381	unser	\N	\N	Bobby	Unser	1934-02-20	American	http://en.wikipedia.org/wiki/Bobby_Unser
382	solana	\N	\N	Moisés	Solana	1935-12-26	Mexican	http://en.wikipedia.org/wiki/Mois%C3%A9s_Solana
383	anderson	\N	\N	Bob	Anderson	1931-05-19	British	http://en.wikipedia.org/wiki/Bob_Anderson_(racing_driver)
384	botha	\N	\N	Luki	Botha	1930-01-16	South African	http://en.wikipedia.org/wiki/Luki_Botha
385	bandini	\N	\N	Lorenzo	Bandini	1935-12-21	Italian	http://en.wikipedia.org/wiki/Lorenzo_Bandini
386	ginther	\N	\N	Richie	Ginther	1930-08-05	American	http://en.wikipedia.org/wiki/Richie_Ginther
387	parkes	\N	\N	Mike	Parkes	1931-09-24	British	http://en.wikipedia.org/wiki/Mike_Parkes
388	irwin	\N	\N	Chris	Irwin	1942-06-27	British	http://en.wikipedia.org/wiki/Chris_Irwin
389	ligier	\N	\N	Guy	Ligier	1930-07-12	French	http://en.wikipedia.org/wiki/Guy_Ligier
390	rees	\N	\N	Alan	Rees	1938-01-12	British	http://en.wikipedia.org/wiki/Alan_Rees_(racing_driver)
391	hart	\N	\N	Brian	Hart	1936-09-07	British	http://en.wikipedia.org/wiki/Brian_Hart
392	fisher	\N	\N	Mike	Fisher	1943-03-13	American	http://en.wikipedia.org/wiki/Mike_Fisher_(driver)
393	tom_jones	\N	\N	Tom	Jones	1943-04-26	American	http://en.wikipedia.org/wiki/Tom_Jones_(auto_racer)
394	baghetti	\N	\N	Giancarlo	Baghetti	1934-12-25	Italian	http://en.wikipedia.org/wiki/Giancarlo_Baghetti
395	williams	\N	\N	Jonathan	Williams	1942-10-26	British	http://en.wikipedia.org/wiki/Jonathan_Williams_(racing_driver)
396	bondurant	\N	\N	Bob	Bondurant	1933-04-27	American	http://en.wikipedia.org/wiki/Bob_Bondurant
397	arundell	\N	\N	Peter	Arundell	1933-11-08	British	http://en.wikipedia.org/wiki/Peter_Arundell
398	vic_wilson	\N	\N	Vic	Wilson	1931-04-14	British	http://en.wikipedia.org/wiki/Vic_Wilson_(motor_racing_driver)
399	taylor	\N	\N	John	Taylor	1933-03-23	British	http://en.wikipedia.org/wiki/John_Taylor_(racer)
400	lawrence	\N	\N	Chris	Lawrence	1933-07-27	British	http://en.wikipedia.org/wiki/Chris_Lawrence_(racing_driver)
401	trevor_taylor	\N	\N	Trevor	Taylor	1936-12-26	British	http://en.wikipedia.org/wiki/Trevor_Taylor
402	geki	\N	\N	Giacomo	Russo	1937-10-23	Italian	http://en.wikipedia.org/wiki/Geki_(driver)
403	phil_hill	\N	\N	Phil	Hill	1927-04-20	American	http://en.wikipedia.org/wiki/Phil_Hill
404	ireland	\N	\N	Innes	Ireland	1930-06-12	British	http://en.wikipedia.org/wiki/Innes_Ireland
405	bucknum	\N	\N	Ronnie	Bucknum	1936-04-05	American	http://en.wikipedia.org/wiki/Ronnie_Bucknum
406	hawkins	\N	\N	Paul	Hawkins	1937-10-12	Australian	http://en.wikipedia.org/wiki/Paul_Hawkins_(racing_driver)
407	prophet	\N	\N	David	Prophet	1937-10-09	British	http://en.wikipedia.org/wiki/David_Prophet
408	maggs	\N	\N	Tony	Maggs	1937-02-09	South African	http://en.wikipedia.org/wiki/Tony_Maggs
409	blokdyk	\N	\N	Trevor	Blokdyk	1935-11-30	South African	http://en.wikipedia.org/wiki/Trevor_Blokdyk
410	lederle	\N	\N	Neville	Lederle	1938-09-25	South African	http://en.wikipedia.org/wiki/Neville_Lederle
411	serrurier	\N	\N	Doug	Serrurier	1920-12-09	South African	http://en.wikipedia.org/wiki/Doug_Serrurier
412	niemann	\N	\N	Brausch	Niemann	1939-01-07	South African	http://en.wikipedia.org/wiki/Brausch_Niemann
413	pieterse	\N	\N	Ernie	Pieterse	1938-07-04	South African	http://en.wikipedia.org/wiki/Ernie_Pieterse
414	puzey	\N	\N	Clive	Puzey	1941-07-11	Rhodesian	http://en.wikipedia.org/wiki/Clive_Puzey
415	reed	\N	\N	Ray	Reed	1932-04-30	South African	http://en.wikipedia.org/wiki/Ray_Reed
416	clapham	\N	\N	David	Clapham	1931-05-18	South African	http://en.wikipedia.org/wiki/David_Clapham
417	blignaut	\N	\N	Alex	Blignaut	1932-11-30	South African	http://en.wikipedia.org/wiki/Alex_Blignaut
418	gregory	\N	\N	Masten	Gregory	1932-02-29	American	http://en.wikipedia.org/wiki/Masten_Gregory
419	rhodes	\N	\N	John	Rhodes	1927-08-18	British	http://en.wikipedia.org/wiki/John_Rhodes_(driver)
420	raby	\N	\N	Ian	Raby	1921-09-22	British	http://en.wikipedia.org/wiki/Ian_Raby
421	rollinson	\N	\N	Alan	Rollinson	1943-05-15	British	http://en.wikipedia.org/wiki/Alan_Rollinson
422	gubby	\N	\N	Brian	Gubby	1934-04-17	British	http://en.wikipedia.org/wiki/Brian_Gubby
423	mitter	\N	\N	Gerhard	Mitter	1935-08-30	German	http://en.wikipedia.org/wiki/Gerhard_Mitter
424	bussinello	\N	\N	Roberto	Bussinello	1927-10-04	Italian	http://en.wikipedia.org/wiki/Roberto_Bussinello
425	vaccarella	\N	\N	Nino	Vaccarella	1933-03-04	Italian	http://en.wikipedia.org/wiki/Nino_Vaccarella
426	bassi	\N	\N	Giorgio	Bassi	1934-01-20	Italian	http://en.wikipedia.org/wiki/Giorgio_Bassi
427	trintignant	\N	\N	Maurice	Trintignant	1917-10-30	French	http://en.wikipedia.org/wiki/Maurice_Trintignant
428	collomb	\N	\N	Bernard	Collomb	1930-10-07	French	http://en.wikipedia.org/wiki/Bernard_Collomb
429	andre_pilette	\N	\N	André	Pilette	1918-10-06	Belgian	http://en.wikipedia.org/wiki/Andr%C3%A9_Pilette
430	beaufort	\N	\N	Carel Godin	de Beaufort	1934-04-10	Dutch	http://en.wikipedia.org/wiki/Carel_Godin_de_Beaufort
431	barth	\N	\N	Edgar	Barth	1917-01-26	German	http://en.wikipedia.org/wiki/Edgar_Barth
432	cabral	\N	\N	Mário de Araújo	Cabral	1934-01-15	Portuguese	http://en.wikipedia.org/wiki/Mario_de_Araujo_Cabral
433	hansgen	\N	\N	Walt	Hansgen	1919-10-28	American	http://en.wikipedia.org/wiki/Walt_Hansgen
434	sharp	\N	\N	Hap	Sharp	1928-01-01	American	http://en.wikipedia.org/wiki/Hap_Sharp
435	mairesse	\N	\N	Willy	Mairesse	1928-10-01	Belgian	http://en.wikipedia.org/wiki/Willy_Mairesse
436	campbell-jones	\N	\N	John	Campbell-Jones	1930-01-21	British	http://en.wikipedia.org/wiki/John_Campbell-Jones
437	burgess	\N	\N	Ian	Burgess	1930-07-06	British	http://en.wikipedia.org/wiki/Ian_Burgess
438	settember	\N	\N	Tony	Settember	1926-07-10	American	http://en.wikipedia.org/wiki/Tony_Settember
439	estefano	\N	\N	Nasif	Estéfano	1932-11-18	Argentine	http://en.wikipedia.org/wiki/Nasif_Est%C3%A9fano
440	hall	\N	\N	Jim	Hall	1935-07-23	American	http://en.wikipedia.org/wiki/Jim_Hall_(race_car_driver)
441	parnell	\N	\N	Tim	Parnell	1932-06-25	British	http://en.wikipedia.org/wiki/Tim_Parnell
442	kuhnke	\N	\N	Kurt	Kuhnke	1910-04-30	German	http://en.wikipedia.org/wiki/Kurt_Kuhnke
443	ernesto_brambilla	\N	\N	Ernesto	Brambilla	1934-01-31	Italian	http://en.wikipedia.org/wiki/Ernesto_Brambilla
444	lippi	\N	\N	Roberto	Lippi	1926-10-17	Italian	http://en.wikipedia.org/wiki/Roberto_Lippi
445	seiffert	\N	\N	Günther	Seiffert	1937-10-18	German	http://en.wikipedia.org/wiki/G%C3%BCnther_Seiffert
446	abate	\N	\N	Carlo	Abate	1932-07-10	Italian	http://en.wikipedia.org/wiki/Carlo_Mario_Abate
447	starrabba	\N	\N	Gaetano	Starrabba	1932-12-03	Italian	http://en.wikipedia.org/wiki/Gaetano_Starrabba
448	broeker	\N	\N	Peter	Broeker	1926-05-15	Canadian	http://en.wikipedia.org/wiki/Peter_Broeker
449	ward	\N	\N	Rodger	Ward	1921-01-10	American	http://en.wikipedia.org/wiki/Rodger_Ward
450	vos	\N	\N	Ernie	de Vos	1941-07-01	Dutch	http://en.wikipedia.org/wiki/Ernie_de_Vos
451	dochnal	\N	\N	Frank	Dochnal	1920-10-08	American	http://en.wikipedia.org/wiki/Frank_Dochnal
452	monarch	\N	\N	Thomas	Monarch	1945-09-03	American	\N
842	gasly	10	GAS	Pierre	Gasly	1996-02-07	French	http://en.wikipedia.org/wiki/Pierre_Gasly
453	lewis	\N	\N	Jackie	Lewis	1936-11-01	British	http://en.wikipedia.org/wiki/Jackie_Lewis
454	ricardo_rodriguez	\N	\N	Ricardo	Rodríguez	1942-02-14	Mexican	http://en.wikipedia.org/wiki/Ricardo_Rodr%C3%ADguez_(Formula_One)
455	seidel	\N	\N	Wolfgang	Seidel	1926-07-04	German	http://en.wikipedia.org/wiki/Wolfgang_Seidel
456	salvadori	\N	\N	Roy	Salvadori	1922-05-12	British	http://en.wikipedia.org/wiki/Roy_Salvadori
457	pon	\N	\N	Ben	Pon	1936-12-09	Dutch	http://en.wikipedia.org/wiki/Ben_Pon
458	slotemaker	\N	\N	Rob	Slotemaker	1929-06-13	Dutch	http://en.wikipedia.org/wiki/Rob_Slotemaker
459	marsh	\N	\N	Tony	Marsh	1931-07-20	British	http://en.wikipedia.org/wiki/Tony_Marsh_(racing_driver)
460	ashmore	\N	\N	Gerry	Ashmore	1936-07-25	British	http://en.wikipedia.org/wiki/Gerry_Ashmore
461	schiller	\N	\N	Heinz	Schiller	1930-01-25	Swiss	http://en.wikipedia.org/wiki/Heinz_Schiller
462	davis	\N	\N	Colin	Davis	1933-07-29	British	http://en.wikipedia.org/wiki/Colin_Davis_(driver)
463	chamberlain	\N	\N	Jay	Chamberlain	1925-12-29	American	http://en.wikipedia.org/wiki/Jay_Chamberlain
464	shelly	\N	\N	Tony	Shelly	1937-02-02	New Zealander	http://en.wikipedia.org/wiki/Tony_Shelly
465	greene	\N	\N	Keith	Greene	1938-01-05	British	http://en.wikipedia.org/wiki/Keith_Greene
466	walter	\N	\N	Heini	Walter	1927-07-28	Swiss	http://en.wikipedia.org/wiki/Heini_Walter
467	prinoth	\N	\N	Ernesto	Prinoth	1923-04-15	Italian	http://en.wikipedia.org/wiki/Ernesto_Prinoth
468	penske	\N	\N	Roger	Penske	1937-02-20	American	http://en.wikipedia.org/wiki/Roger_Penske
469	schroeder	\N	\N	Rob	Schroeder	1926-05-11	British	http://en.wikipedia.org/wiki/Rob_Schroeder
470	mayer	\N	\N	Timmy	Mayer	1938-02-22	American	http://en.wikipedia.org/wiki/Timmy_Mayer
471	johnstone	\N	\N	Bruce	Johnstone	1937-01-30	South African	http://en.wikipedia.org/wiki/Bruce_Johnstone_(racing_driver)
472	harris	\N	\N	Mike	Harris	1939-05-25	South African	http://en.wikipedia.org/wiki/Mike_Harris_(race_car_driver)
473	hocking	\N	\N	Gary	Hocking	1937-09-30	Rhodesian	http://en.wikipedia.org/wiki/Gary_Hocking
474	vyver	\N	\N	Syd	van der Vyver	1920-06-01	South African	http://en.wikipedia.org/wiki/Syd_van_der_Vyver
475	moss	\N	\N	Stirling	Moss	1929-09-17	British	http://en.wikipedia.org/wiki/Stirling_Moss
476	trips	\N	\N	Wolfgang	von Trips	1928-05-04	German	http://en.wikipedia.org/wiki/Wolfgang_Graf_Berghe_von_Trips
477	allison	\N	\N	Cliff	Allison	1932-02-08	British	http://en.wikipedia.org/wiki/Cliff_Allison
478	herrmann	\N	\N	Hans	Herrmann	1928-02-23	German	http://en.wikipedia.org/wiki/Hans_Herrmann
479	brooks	\N	\N	Tony	Brooks	1932-02-25	British	http://en.wikipedia.org/wiki/Tony_Brooks
480	may	\N	\N	Michael	May	1934-08-18	Swiss	http://en.wikipedia.org/wiki/Michael_May_(racing_driver)
481	henry_taylor	\N	\N	Henry	Taylor	1932-12-16	British	http://en.wikipedia.org/wiki/Henry_Taylor_(racing_driver)
482	gendebien	\N	\N	Olivier	Gendebien	1924-01-12	Belgian	http://en.wikipedia.org/wiki/Olivier_Gendebien
483	scarlatti	\N	\N	Giorgio	Scarlatti	1921-10-02	Italian	http://en.wikipedia.org/wiki/Giorgio_Scarlatti
484	naylor	\N	\N	Brian	Naylor	1923-03-24	British	http://en.wikipedia.org/wiki/Brian_Naylor
485	bordeu	\N	\N	Juan Manuel	Bordeu	1934-01-28	Argentine	http://en.wikipedia.org/wiki/Juan_Manuel_Bordeu
486	fairman	\N	\N	Jack	Fairman	1913-03-15	British	http://en.wikipedia.org/wiki/Jack_Fairman
487	natili	\N	\N	Massimo	Natili	1935-07-28	Italian	http://en.wikipedia.org/wiki/Massimo_Natili
488	monteverdi	\N	\N	Peter	Monteverdi	1934-06-07	Swiss	http://en.wikipedia.org/wiki/Peter_Monteverdi
489	pirocchi	\N	\N	Renato	Pirocchi	1933-03-26	Italian	http://en.wikipedia.org/wiki/Renato_Pirocchi
490	duke	\N	\N	Geoff	Duke	1923-03-29	British	http://en.wikipedia.org/wiki/Geoff_Duke
491	thiele	\N	\N	Alfonso	Thiele	1920-04-05	American-Italian	http://en.wikipedia.org/wiki/Alfonso_Thiele
492	boffa	\N	\N	Menato	Boffa	1930-01-04	Italian	http://en.wikipedia.org/wiki/Menato_Boffa
493	ryan	\N	\N	Peter	Ryan	1940-06-10	Canadian	http://en.wikipedia.org/wiki/Peter_Ryan_(driver)
494	ruby	\N	\N	Lloyd	Ruby	1928-01-12	American	http://en.wikipedia.org/wiki/Lloyd_Ruby
495	ken_miles	\N	\N	Ken	Miles	1918-11-01	British	http://en.wikipedia.org/wiki/Ken_Miles
496	menditeguy	\N	\N	Carlos	Menditeguy	1914-08-10	Argentine	http://en.wikipedia.org/wiki/Carlos_Menditeguy
497	larreta	\N	\N	Alberto Rodriguez	Larreta	1934-01-14	Argentine	http://en.wikipedia.org/wiki/Alberto_Rodriguez_Larreta
498	gonzalez	\N	\N	José Froilán	González	1922-10-05	Argentine	http://en.wikipedia.org/wiki/Jos%C3%A9_Froil%C3%A1n_Gonz%C3%A1lez
499	bonomi	\N	\N	Roberto	Bonomi	1919-09-30	Argentine	http://en.wikipedia.org/wiki/Roberto_Bonomi
500	munaron	\N	\N	Gino	Munaron	1928-04-02	Italian	http://en.wikipedia.org/wiki/Gino_Munaron
501	schell	\N	\N	Harry	Schell	1921-06-29	American	http://en.wikipedia.org/wiki/Harry_Schell
502	stacey	\N	\N	Alan	Stacey	1933-08-29	British	http://en.wikipedia.org/wiki/Alan_Stacey
503	chimeri	\N	\N	Ettore	Chimeri	1921-06-04	Venezuelan	http://en.wikipedia.org/wiki/Ettore_Chimeri
504	creus	\N	\N	Antonio	Creus	1924-10-28	Spanish	http://en.wikipedia.org/wiki/Antonio_Creus
505	bristow	\N	\N	Chris	Bristow	1937-12-02	British	http://en.wikipedia.org/wiki/Chris_Bristow
506	halford	\N	\N	Bruce	Halford	1931-05-18	British	http://en.wikipedia.org/wiki/Bruce_Halford
507	daigh	\N	\N	Chuck	Daigh	1923-11-29	American	http://en.wikipedia.org/wiki/Chuck_Daigh
508	reventlow	\N	\N	Lance	Reventlow	1936-02-24	American	http://en.wikipedia.org/wiki/Lance_Reventlow
509	rathmann	\N	\N	Jim	Rathmann	1928-07-16	American	http://en.wikipedia.org/wiki/Jim_Rathmann
510	goldsmith	\N	\N	Paul	Goldsmith	1925-10-02	American	http://en.wikipedia.org/wiki/Paul_Goldsmith
511	branson	\N	\N	Don	Branson	1920-06-02	American	http://en.wikipedia.org/wiki/Don_Branson
512	thomson	\N	\N	Johnny	Thomson	1922-04-09	American	http://en.wikipedia.org/wiki/Johnny_Thomson
513	johnson	\N	\N	Eddie	Johnson	1919-02-10	American	http://en.wikipedia.org/wiki/Eddie_Johnson_(auto_racer)
514	veith	\N	\N	Bob	Veith	1926-11-01	American	http://en.wikipedia.org/wiki/Bob_Veith
515	tingelstad	\N	\N	Bud	Tingelstad	1928-04-04	American	http://en.wikipedia.org/wiki/Bud_Tingelstad
516	christie	\N	\N	Bob	Christie	1924-04-04	American	http://en.wikipedia.org/wiki/Bob_Christie_(racing_driver)
517	amick	\N	\N	Red	Amick	1929-01-19	American	http://en.wikipedia.org/wiki/Red_Amick
518	darter	\N	\N	Duane	Carter	1913-05-05	American	http://en.wikipedia.org/wiki/Duane_Carter
519	homeier	\N	\N	Bill	Homeier	1918-08-31	American	http://en.wikipedia.org/wiki/Bill_Homeier
520	hartley	\N	\N	Gene	Hartley	1926-01-28	American	http://en.wikipedia.org/wiki/Gene_Hartley
521	stevenson	\N	\N	Chuck	Stevenson	1919-10-15	American	http://en.wikipedia.org/wiki/Chuck_Stevenson
522	grim	\N	\N	Bobby	Grim	1924-09-04	American	http://en.wikipedia.org/wiki/Bobby_Grim
523	templeman	\N	\N	Shorty	Templeman	1919-08-12	American	http://en.wikipedia.org/wiki/Shorty_Templeman
524	hurtubise	\N	\N	Jim	Hurtubise	1932-12-05	American	http://en.wikipedia.org/wiki/Jim_Hurtubise
525	bryan	\N	\N	Jimmy	Bryan	1926-01-28	American	http://en.wikipedia.org/wiki/Jimmy_Bryan
526	ruttman	\N	\N	Troy	Ruttman	1930-03-11	American	http://en.wikipedia.org/wiki/Troy_Ruttman
527	sachs	\N	\N	Eddie	Sachs	1927-05-28	American	http://en.wikipedia.org/wiki/Eddie_Sachs
528	freeland	\N	\N	Don	Freeland	1925-03-25	American	http://en.wikipedia.org/wiki/Don_Freeland
529	bettenhausen	\N	\N	Tony	Bettenhausen	1916-09-12	American	http://en.wikipedia.org/wiki/Tony_Bettenhausen
530	weiler	\N	\N	Wayne	Weiler	1934-12-09	American	http://en.wikipedia.org/wiki/Wayne_Weiler
531	foyt	\N	\N	Anthony	Foyt	1935-01-16	American	http://en.wikipedia.org/wiki/A.J._Foyt
532	russo	\N	\N	Eddie	Russo	1925-11-19	American	http://en.wikipedia.org/wiki/Eddie_Russo
533	boyd	\N	\N	Johnny	Boyd	1926-08-19	American	http://en.wikipedia.org/wiki/Johnny_Boyd
534	force	\N	\N	Gene	Force	1916-06-15	American	http://en.wikipedia.org/wiki/Gene_Force
535	mcwithey	\N	\N	Jim	McWithey	1927-07-04	American	http://en.wikipedia.org/wiki/Jim_McWithey
536	sutton	\N	\N	Len	Sutton	1925-08-09	American	http://en.wikipedia.org/wiki/Len_Sutton
537	dick_rathmann	\N	\N	Dick	Rathmann	1924-01-06	American	http://en.wikipedia.org/wiki/Dick_Rathmann
538	herman	\N	\N	Al	Herman	1927-03-15	American	http://en.wikipedia.org/wiki/Al_Herman
539	dempsey_wilson	\N	\N	Dempsey	Wilson	1927-03-11	American	http://en.wikipedia.org/wiki/Dempsey_Wilson
540	mike_taylor	\N	\N	Mike	Taylor	1934-04-24	British	http://en.wikipedia.org/wiki/Mike_Taylor_(driver)
541	flockhart	\N	\N	Ron	Flockhart	1923-06-16	British	http://en.wikipedia.org/wiki/Ron_Flockhart_(auto_racing)
542	piper	\N	\N	David	Piper	1930-12-02	British	http://en.wikipedia.org/wiki/David_Piper
543	cabianca	\N	\N	Giulio	Cabianca	1923-02-19	Italian	http://en.wikipedia.org/wiki/Giulio_Cabianca
544	drogo	\N	\N	Piero	Drogo	1926-08-08	Italian	http://en.wikipedia.org/wiki/Piero_Drogo
545	gamble	\N	\N	Fred	Gamble	1932-03-17	American	http://en.wikipedia.org/wiki/Fred_Gamble_(racing_driver)
546	owen	\N	\N	Arthur	Owen	1915-03-23	British	http://en.wikipedia.org/wiki/Arthur_Owen
547	gould	\N	\N	Horace	Gould	1918-09-20	British	http://en.wikipedia.org/wiki/Horace_Gould
548	drake	\N	\N	Bob	Drake	1919-12-14	American	http://en.wikipedia.org/wiki/Bob_Drake_(Formula_One)
549	bueb	\N	\N	Ivor	Bueb	1923-06-06	British	http://en.wikipedia.org/wiki/Ivor_Bueb
550	changy	\N	\N	Alain	de Changy	1922-02-05	Belgian	http://en.wikipedia.org/wiki/Alain_de_Changy
551	filippis	\N	\N	Maria	de Filippis	1926-11-11	Italian	http://en.wikipedia.org/wiki/Maria_Teresa_de_Filippis
552	lucienbonnet	\N	\N	Jean	Lucienbonnet	1923-01-07	French	http://en.wikipedia.org/wiki/Jean_Lucienbonnet
553	testut	\N	\N	André	Testut	1926-04-13	Monegasque	http://en.wikipedia.org/wiki/Andr%C3%A9_Testut
554	behra	\N	\N	Jean	Behra	1921-02-16	French	http://en.wikipedia.org/wiki/Jean_Behra
555	paul_russo	\N	\N	Paul	Russo	1914-04-10	American	http://en.wikipedia.org/wiki/Paul_Russo
556	daywalt	\N	\N	Jimmy	Daywalt	1924-08-28	American	http://en.wikipedia.org/wiki/Jimmy_Daywalt
557	arnold	\N	\N	Chuck	Arnold	1926-05-30	American	http://en.wikipedia.org/wiki/Chuck_Arnold
558	keller	\N	\N	Al	Keller	1920-04-11	American	http://en.wikipedia.org/wiki/Al_Keller
559	flaherty	\N	\N	Pat	Flaherty	1926-01-06	American	http://en.wikipedia.org/wiki/Pat_Flaherty_(racing_driver)
560	cheesbourg	\N	\N	Bill	Cheesbourg	1927-06-12	American	http://en.wikipedia.org/wiki/Bill_Cheesbourg
561	ray_crawford	\N	\N	Ray	Crawford	1915-10-26	American	http://en.wikipedia.org/wiki/Ray_Crawford
562	turner	\N	\N	Jack	Turner	1920-02-12	American	http://en.wikipedia.org/wiki/Jack_Turner_(driver)
563	weyant	\N	\N	Chuck	Weyant	1923-04-03	American	http://en.wikipedia.org/wiki/Chuck_Weyant
564	larson	\N	\N	Jud	Larson	1923-01-21	American	http://en.wikipedia.org/wiki/Jud_Larson
565	magill	\N	\N	Mike	Magill	1920-02-08	American	http://en.wikipedia.org/wiki/Mike_Magill
566	shelby	\N	\N	Carroll	Shelby	1923-01-11	American	http://en.wikipedia.org/wiki/Carroll_Shelby
567	orey	\N	\N	Fritz	d'Orey	1938-03-25	Brazilian	http://en.wikipedia.org/wiki/Fritz_d%27Orey
568	fontes	\N	\N	Azdrubal	Fontes	1922-12-26	Uruguayan	http://en.wikipedia.org/wiki/Azdrubal_Fontes
569	ashdown	\N	\N	Peter	Ashdown	1934-10-16	British	http://en.wikipedia.org/wiki/Peter_Ashdown
570	bill_moss	\N	\N	Bill	Moss	1933-09-04	British	http://en.wikipedia.org/wiki/Bill_Moss_(racing_driver)
571	dennis_taylor	\N	\N	Dennis	Taylor	1921-06-12	British	http://en.wikipedia.org/wiki/Dennis_Taylor_(racing_driver)
572	blanchard	\N	\N	Harry	Blanchard	1929-06-13	American	http://en.wikipedia.org/wiki/Harry_Blanchard
573	tomaso	\N	\N	Alessandro	de Tomaso	1928-07-10	Argentine-Italian	http://en.wikipedia.org/wiki/Alessandro_de_Tomaso
574	constantine	\N	\N	George	Constantine	1918-02-22	American	http://en.wikipedia.org/wiki/George_Constantine
575	said	\N	\N	Bob	Said	1932-05-05	American	http://en.wikipedia.org/wiki/Bob_Said
576	cade	\N	\N	Phil	Cade	1916-06-12	American	http://en.wikipedia.org/wiki/Phil_Cade
577	musso	\N	\N	Luigi	Musso	1924-07-28	Italian	http://en.wikipedia.org/wiki/Luigi_Musso
578	hawthorn	\N	\N	Mike	Hawthorn	1929-04-10	British	http://en.wikipedia.org/wiki/Mike_Hawthorn
579	fangio	\N	\N	Juan	Fangio	1911-06-24	Argentine	http://en.wikipedia.org/wiki/Juan_Manuel_Fangio
580	godia	\N	\N	Paco	Godia	1921-03-21	Spanish	http://en.wikipedia.org/wiki/Paco_Godia
581	collins	\N	\N	Peter	Collins	1931-11-06	British	http://en.wikipedia.org/wiki/Peter_Collins_(racing_driver)
582	kavanagh	\N	\N	Ken	Kavanagh	1923-12-12	Australian	http://en.wikipedia.org/wiki/Ken_Kavanagh
583	gerini	\N	\N	Gerino	Gerini	1928-08-10	Italian	http://en.wikipedia.org/wiki/Gerino_Gerini_(racing_driver)
584	kessler	\N	\N	Bruce	Kessler	1936-03-23	American	http://en.wikipedia.org/wiki/Bruce_Kessler
585	emery	\N	\N	Paul	Emery	1916-11-12	British	http://en.wikipedia.org/wiki/Paul_Emery
586	piotti	\N	\N	Luigi	Piotti	1913-10-27	Italian	http://en.wikipedia.org/wiki/Luigi_Piotti
587	ecclestone	\N	\N	Bernie	Ecclestone	1930-10-28	British	http://en.wikipedia.org/wiki/Bernie_Ecclestone
588	taramazzo	\N	\N	Luigi	Taramazzo	1932-05-05	Italian	http://en.wikipedia.org/wiki/Luigi_Taramazzo
589	chiron	\N	\N	Louis	Chiron	1899-08-03	Monegasque	http://en.wikipedia.org/wiki/Louis_Chiron
590	lewis-evans	\N	\N	Stuart	Lewis-Evans	1930-04-20	British	http://en.wikipedia.org/wiki/Stuart_Lewis-Evans
591	george_amick	\N	\N	George	Amick	1924-10-24	American	http://en.wikipedia.org/wiki/George_Amick
592	reece	\N	\N	Jimmy	Reece	1929-11-17	American	http://en.wikipedia.org/wiki/Jimmy_Reece
593	parsons	\N	\N	Johnnie	Parsons	1918-07-04	American	http://en.wikipedia.org/wiki/Johnnie_Parsons
594	tolan	\N	\N	Johnnie	Tolan	1917-10-22	American	http://en.wikipedia.org/wiki/Johnnie_Tolan
595	garrett	\N	\N	Billy	Garrett	1933-04-24	American	http://en.wikipedia.org/wiki/Billy_Garrett
596	elisian	\N	\N	Ed	Elisian	1926-12-09	American	http://en.wikipedia.org/wiki/Ed_Elisian
597	connor	\N	\N	Pat	O'Connor	1928-10-09	American	http://en.wikipedia.org/wiki/Pat_O%27Connor_(auto_racer)
598	jerry_unser	\N	\N	Jerry	Unser	1932-11-15	American	http://en.wikipedia.org/wiki/Jerry_Unser
599	bisch	\N	\N	Art	Bisch	1926-11-10	American	http://en.wikipedia.org/wiki/Art_Bisch
600	goethals	\N	\N	Christian	Goethals	1928-08-04	Belgian	http://en.wikipedia.org/wiki/Christian_Goethals
601	gibson	\N	\N	Dick	Gibson	1918-04-16	British	http://en.wikipedia.org/wiki/Dick_Gibson
602	la_caze	\N	\N	Robert	La Caze	1917-02-26	French	http://en.wikipedia.org/wiki/Robert_La_Caze
603	guelfi	\N	\N	André	Guelfi	1919-05-06	French	http://en.wikipedia.org/wiki/Andr%C3%A9_Guelfi
604	picard	\N	\N	François	Picard	1921-04-26	French	http://en.wikipedia.org/wiki/Fran%C3%A7ois_Picard
605	bridger	\N	\N	Tom	Bridger	1934-06-24	British	http://en.wikipedia.org/wiki/Tom_Bridger
606	portago	\N	\N	Alfonso	de Portago	1928-10-11	Spanish	http://en.wikipedia.org/wiki/Alfonso_de_Portago
607	perdisa	\N	\N	Cesare	Perdisa	1932-10-21	Italian	http://en.wikipedia.org/wiki/Cesare_Perdisa
608	castellotti	\N	\N	Eugenio	Castellotti	1930-10-10	Italian	http://en.wikipedia.org/wiki/Eugenio_Castellotti
609	simon	\N	\N	André	Simon	1920-01-05	French	http://en.wikipedia.org/wiki/Andr%C3%A9_Simon_(racing_driver)
610	leston	\N	\N	Les	Leston	1920-12-16	British	http://en.wikipedia.org/wiki/Les_Leston
611	hanks	\N	\N	Sam	Hanks	1914-07-13	American	http://en.wikipedia.org/wiki/Sam_Hanks
612	linden	\N	\N	Andy	Linden	1922-04-05	American	http://en.wikipedia.org/wiki/Andy_Linden_(racing_driver)
613	teague	\N	\N	Marshall	Teague	1921-02-22	American	http://en.wikipedia.org/wiki/Marshall_Teague
614	edmunds	\N	\N	Don	Edmunds	1930-09-23	American	http://en.wikipedia.org/wiki/Don_Edmunds
615	agabashian	\N	\N	Fred	Agabashian	1913-08-21	American	http://en.wikipedia.org/wiki/Fred_Agabashian
616	george	\N	\N	Elmer	George	1928-07-15	American	http://en.wikipedia.org/wiki/Elmer_George
617	macdowel	\N	\N	Mike	MacDowel	1932-09-13	British	http://en.wikipedia.org/wiki/Mike_MacDowel
618	mackay-fraser	\N	\N	Herbert	MacKay-Fraser	1927-06-23	American	http://en.wikipedia.org/wiki/Herbert_MacKay-Fraser
619	gerard	\N	\N	Bob	Gerard	1914-01-19	British	http://en.wikipedia.org/wiki/Bob_Gerard
620	maglioli	\N	\N	Umberto	Maglioli	1928-06-05	Italian	http://en.wikipedia.org/wiki/Umberto_Maglioli
621	england	\N	\N	Paul	England	1929-03-28	Australian	http://en.wikipedia.org/wiki/Paul_England
622	landi	\N	\N	Chico	Landi	1907-07-14	Brazilian	http://en.wikipedia.org/wiki/Chico_Landi
623	uria	\N	\N	Alberto	Uria	1924-07-11	Uruguayan	http://en.wikipedia.org/wiki/Alberto_Uria
624	ramos	\N	\N	Hernando	da Silva Ramos	1925-12-07	Brazilian	http://en.wikipedia.org/wiki/Hernando_da_Silva_Ramos
625	bayol	\N	\N	Élie	Bayol	1914-02-28	French	http://en.wikipedia.org/wiki/%C3%89lie_Bayol
626	manzon	\N	\N	Robert	Manzon	1917-04-12	French	http://en.wikipedia.org/wiki/Robert_Manzon
627	rosier	\N	\N	Louis	Rosier	1905-11-05	French	http://en.wikipedia.org/wiki/Louis_Rosier
628	sweikert	\N	\N	Bob	Sweikert	1926-05-20	American	http://en.wikipedia.org/wiki/Bob_Sweikert
629	griffith	\N	\N	Cliff	Griffith	1916-02-06	American	http://en.wikipedia.org/wiki/Cliff_Griffith
630	dinsmore	\N	\N	Duke	Dinsmore	1913-04-10	American	http://en.wikipedia.org/wiki/Duke_Dinsmore
631	andrews	\N	\N	Keith	Andrews	1920-06-15	American	http://en.wikipedia.org/wiki/Keith_Andrews_(driver)
632	frere	\N	\N	Paul	Frère	1917-01-30	Belgian	http://en.wikipedia.org/wiki/Paul_Fr%C3%A8re
633	villoresi	\N	\N	Luigi	Villoresi	1909-05-16	Italian	http://en.wikipedia.org/wiki/Luigi_Villoresi
634	scotti	\N	\N	Piero	Scotti	1909-11-11	Italian	http://en.wikipedia.org/wiki/Piero_Scotti
635	chapman	\N	\N	Colin	Chapman	1928-05-19	British	http://en.wikipedia.org/wiki/Colin_Chapman
636	titterington	\N	\N	Desmond	Titterington	1928-05-01	British	http://en.wikipedia.org/wiki/Desmond_Titterington
637	scott_Brown	\N	\N	Archie	Scott Brown	1927-05-13	British	http://en.wikipedia.org/wiki/Archie_Scott_Brown
638	volonterio	\N	\N	Ottorino	Volonterio	1917-12-07	Swiss	http://en.wikipedia.org/wiki/Ottorino_Volonterio
639	milhoux	\N	\N	André	Milhoux	1928-12-09	Belgian	http://en.wikipedia.org/wiki/Andr%C3%A9_Milhoux
640	graffenried	\N	\N	Toulo	de Graffenried	1914-05-18	Swiss	http://en.wikipedia.org/wiki/Toulo_de_Graffenried
641	taruffi	\N	\N	Piero	Taruffi	1906-10-12	Italian	http://en.wikipedia.org/wiki/Piero_Taruffi
642	farina	\N	\N	Nino	Farina	1906-10-30	Italian	http://en.wikipedia.org/wiki/Nino_Farina
643	mieres	\N	\N	Roberto	Mieres	1924-12-03	Argentine	http://en.wikipedia.org/wiki/Roberto_Mieres
644	mantovani	\N	\N	Sergio	Mantovani	1929-05-22	Italian	http://en.wikipedia.org/wiki/Sergio_Mantovani
645	bucci	\N	\N	Clemar	Bucci	1920-09-04	Argentine	http://en.wikipedia.org/wiki/Clemar_Bucci
646	iglesias	\N	\N	Jesús	Iglesias	1922-02-22	Argentine	http://en.wikipedia.org/wiki/Jes%C3%BAs_Iglesias
647	ascari	\N	\N	Alberto	Ascari	1918-07-13	Italian	http://en.wikipedia.org/wiki/Alberto_Ascari
648	kling	\N	\N	Karl	Kling	1910-09-16	German	http://en.wikipedia.org/wiki/Karl_Kling
649	birger	\N	\N	Pablo	Birger	1924-01-07	Argentine	http://en.wikipedia.org/wiki/Pablo_Birger
650	pollet	\N	\N	Jacques	Pollet	1922-07-02	French	http://en.wikipedia.org/wiki/Jacques_Pollet
651	macklin	\N	\N	Lance	Macklin	1919-09-02	British	http://en.wikipedia.org/wiki/Lance_Macklin
652	whiteaway	\N	\N	Ted	Whiteaway	1928-11-01	British	http://en.wikipedia.org/wiki/Ted_Whiteaway
653	davies	\N	\N	Jimmy	Davies	1929-08-08	American	http://en.wikipedia.org/wiki/Jimmy_Davies
654	faulkner	\N	\N	Walt	Faulkner	1920-02-16	American	http://en.wikipedia.org/wiki/Walt_Faulkner
655	niday	\N	\N	Cal	Niday	1914-04-29	American	http://en.wikipedia.org/wiki/Cal_Niday
656	cross	\N	\N	Art	Cross	1918-01-24	American	http://en.wikipedia.org/wiki/Art_Cross
657	vukovich	\N	\N	Bill	Vukovich	1918-12-13	American	http://en.wikipedia.org/wiki/Bill_Vukovich
658	mcgrath	\N	\N	Jack	McGrath	1919-10-08	American	http://en.wikipedia.org/wiki/Jack_McGrath_(racing_driver)
659	hoyt	\N	\N	Jerry	Hoyt	1929-01-29	American	http://en.wikipedia.org/wiki/Jerry_Hoyt
660	claes	\N	\N	Johnny	Claes	1916-08-11	Belgian	http://en.wikipedia.org/wiki/Johnny_Claes
661	peter_walker	\N	\N	Peter	Walker	1912-10-07	British	http://en.wikipedia.org/wiki/Peter_Walker_(driver)
662	sparken	\N	\N	Mike	Sparken	1930-06-16	French	http://en.wikipedia.org/wiki/Mike_Sparken
663	wharton	\N	\N	Ken	Wharton	1916-03-21	British	http://en.wikipedia.org/wiki/Ken_Wharton
664	mcalpine	\N	\N	Kenneth	McAlpine	1920-09-21	British	http://en.wikipedia.org/wiki/Kenneth_McAlpine
665	marr	\N	\N	Leslie	Marr	1922-08-14	British	http://en.wikipedia.org/wiki/Leslie_Marr
666	rolt	\N	\N	Tony	Rolt	1918-10-16	British	http://en.wikipedia.org/wiki/Tony_Rolt
667	fitch	\N	\N	John	Fitch	1917-08-04	American	http://en.wikipedia.org/wiki/John_Fitch_(driver)
668	lucas	\N	\N	Jean	Lucas	1917-04-25	French	http://en.wikipedia.org/wiki/Jean_Lucas
669	bira	\N	\N	Prince	Bira	1914-07-15	Thai	http://en.wikipedia.org/wiki/Prince_Bira
670	marimon	\N	\N	Onofre	Marimón	1923-12-19	Argentine	http://en.wikipedia.org/wiki/Onofre_Marim%C3%B3n
671	loyer	\N	\N	Roger	Loyer	1907-08-05	French	http://en.wikipedia.org/wiki/Roger_Loyer
672	daponte	\N	\N	Jorge	Daponte	1923-06-05	Argentine	http://en.wikipedia.org/wiki/Jorge_Daponte
673	nazaruk	\N	\N	Mike	Nazaruk	1921-10-02	American	http://en.wikipedia.org/wiki/Mike_Nazaruk
674	crockett	\N	\N	Larry	Crockett	1926-10-23	American	http://en.wikipedia.org/wiki/Larry_Crockett
675	ayulo	\N	\N	Manny	Ayulo	1921-10-20	American	http://en.wikipedia.org/wiki/Manny_Ayulo
676	armi	\N	\N	Frank	Armi	1918-10-12	American	http://en.wikipedia.org/wiki/Frank_Armi
677	webb	\N	\N	Travis	Webb	1910-10-08	American	http://en.wikipedia.org/wiki/Travis_Webb
678	duncan	\N	\N	Len	Duncan	1911-07-25	American	http://en.wikipedia.org/wiki/Len_Duncan
679	mccoy	\N	\N	Ernie	McCoy	1921-02-19	American	http://en.wikipedia.org/wiki/Ernie_McCoy
680	swaters	\N	\N	Jacques	Swaters	1926-10-30	American	http://en.wikipedia.org/wiki/Jacques_Swaters
681	georges_berger	\N	\N	Georges	Berger	1918-09-14	Belgian	http://en.wikipedia.org/wiki/Georges_Berger
682	beauman	\N	\N	Don	Beauman	1928-07-26	British	http://en.wikipedia.org/wiki/Don_Beauman
683	thorne	\N	\N	Leslie	Thorne	1916-06-23	British	http://en.wikipedia.org/wiki/Leslie_Thorne
684	whitehouse	\N	\N	Bill	Whitehouse	1909-04-01	British	http://en.wikipedia.org/wiki/Bill_Whitehouse
685	riseley_prichard	\N	\N	John	Riseley-Prichard	1924-01-17	British	http://en.wikipedia.org/wiki/John_Riseley-Prichard
686	reg_parnell	\N	\N	Reg	Parnell	1911-07-02	British	http://en.wikipedia.org/wiki/Reg_Parnell
687	whitehead	\N	\N	Peter	Whitehead	1914-11-12	British	http://en.wikipedia.org/wiki/Peter_Whitehead_(racing_driver)
688	brandon	\N	\N	Eric	Brandon	1920-07-18	British	http://en.wikipedia.org/wiki/Eric_Brandon
689	alan_brown	\N	\N	Alan	Brown	1919-11-20	British	http://en.wikipedia.org/wiki/Alan_Brown_(racing_driver)
690	nuckey	\N	\N	Rodney	Nuckey	1929-06-26	British	http://en.wikipedia.org/wiki/Rodney_Nuckey
691	lang	\N	\N	Hermann	Lang	1909-04-06	German	http://en.wikipedia.org/wiki/Hermann_Lang
692	helfrich	\N	\N	Theo	Helfrich	1913-05-13	German	http://en.wikipedia.org/wiki/Theo_Helfrich
693	wacker	\N	\N	Fred	Wacker	1918-07-10	American	http://en.wikipedia.org/wiki/Fred_Wacker
694	riu	\N	\N	Giovanni	de Riu	1925-03-10	Italian	http://en.wikipedia.org/wiki/Giovanni_de_Riu
695	galvez	\N	\N	Oscar	Gálvez	1913-08-17	Argentine	http://en.wikipedia.org/wiki/%C3%93scar_Alfredo_G%C3%A1lvez
696	john_barber	\N	\N	John	Barber	1929-07-22	British	http://en.wikipedia.org/wiki/John_Barber_(racing_driver)
697	bonetto	\N	\N	Felice	Bonetto	1903-06-09	Italian	http://en.wikipedia.org/wiki/Felice_Bonetto
698	cruz	\N	\N	Adolfo	Cruz	1923-06-28	Argentine	http://en.wikipedia.org/wiki/Adolfo_Schewelm_Cruz
699	nalon	\N	\N	Duke	Nalon	1913-03-02	American	http://en.wikipedia.org/wiki/Duke_Nalon
700	scarborough	\N	\N	Carl	Scarborough	1914-07-03	American	http://en.wikipedia.org/wiki/Carl_Scarborough
701	holland	\N	\N	Bill	Holland	1907-12-18	American	http://en.wikipedia.org/wiki/Bill_Holland
702	bob_scott	\N	\N	Bob	Scott	1928-10-04	American	http://en.wikipedia.org/wiki/Bob_Scott_(auto_racer)
703	legat	\N	\N	Arthur	Legat	1898-11-01	Belgian	http://en.wikipedia.org/wiki/Arthur_Legat
704	cabantous	\N	\N	Yves	Cabantous	1904-10-08	French	http://en.wikipedia.org/wiki/Yves_Giraud_Cabantous
705	crook	\N	\N	Tony	Crook	1920-02-16	British	http://en.wikipedia.org/wiki/Tony_Crook
706	jimmy_stewart	\N	\N	Jimmy	Stewart	1931-03-06	British	http://en.wikipedia.org/wiki/Jimmy_Stewart_(racing_driver)
707	ian_stewart	\N	\N	Ian	Stewart	1929-07-15	British	http://en.wikipedia.org/wiki/Ian_Stewart_(racing_driver)
708	duncan_hamilton	\N	\N	Duncan	Hamilton	1920-04-30	British	http://en.wikipedia.org/wiki/Duncan_Hamilton_(racing_driver)
709	klodwig	\N	\N	Ernst	Klodwig	1903-05-23	East German	http://en.wikipedia.org/wiki/Ernst_Klodwig
710	krause	\N	\N	Rudolf	Krause	1907-03-30	East German	http://en.wikipedia.org/wiki/Rudolf_Krause
711	karch	\N	\N	Oswald	Karch	1917-03-06	German	http://en.wikipedia.org/wiki/Oswald_Karch
712	heeks	\N	\N	Willi	Heeks	1922-02-13	German	http://en.wikipedia.org/wiki/Willi_Heeks
713	fitzau	\N	\N	Theo	Fitzau	1923-02-10	East German	http://en.wikipedia.org/wiki/Theo_Fitzau
714	adolff	\N	\N	Kurt	Adolff	1921-11-05	German	http://en.wikipedia.org/wiki/Kurt_Adolff
715	bechem	\N	\N	Günther	Bechem	1921-12-21	German	http://en.wikipedia.org/wiki/G%C3%BCnther_Bechem
716	bauer	\N	\N	Erwin	Bauer	1912-07-17	German	http://en.wikipedia.org/wiki/Erwin_Bauer
717	hans_stuck	\N	\N	Hans	von Stuck	1900-12-27	German	http://en.wikipedia.org/wiki/Hans_Von_Stuck
718	loof	\N	\N	Ernst	Loof	1907-07-04	German	http://en.wikipedia.org/wiki/Ernst_Loof
719	scherrer	\N	\N	Albert	Scherrer	1908-02-28	Swiss	http://en.wikipedia.org/wiki/Albert_Scherrer
720	terra	\N	\N	Max	de Terra	1918-10-06	Swiss	http://en.wikipedia.org/wiki/Max_de_Terra
721	hirt	\N	\N	Peter	Hirt	1910-03-30	Swiss	http://en.wikipedia.org/wiki/Peter_Hirt
722	carini	\N	\N	Piero	Carini	1921-03-06	Italian	http://en.wikipedia.org/wiki/Piero_Carini
723	fischer	\N	\N	Rudi	Fischer	1912-04-19	Swiss	http://en.wikipedia.org/wiki/Rudi_Fischer
724	ulmen	\N	\N	Toni	Ulmen	1906-01-25	German	http://en.wikipedia.org/wiki/Toni_Ulmen
725	abecassis	\N	\N	George	Abecassis	1913-03-21	British	http://en.wikipedia.org/wiki/George_Abecassis
726	george_connor	\N	\N	George	Connor	1906-08-16	American	http://en.wikipedia.org/wiki/George_Connor_(driver)
727	rigsby	\N	\N	Jim	Rigsby	1923-06-06	American	http://en.wikipedia.org/wiki/Jim_Rigsby
728	james	\N	\N	Joe	James	1925-05-23	American	http://en.wikipedia.org/wiki/Joe_James_(racing_driver)
729	schindler	\N	\N	Bill	Schindler	1909-03-06	American	http://en.wikipedia.org/wiki/Bill_Schindler
730	fonder	\N	\N	George	Fonder	1917-06-22	American	http://en.wikipedia.org/wiki/George_Fonder
731	banks	\N	\N	Henry	Banks	1913-06-14	American	http://en.wikipedia.org/wiki/Henry_Banks
732	mcdowell	\N	\N	Johnny	McDowell	1915-01-29	American	http://en.wikipedia.org/wiki/Johnny_McDowell
733	miller	\N	\N	Chet	Miller	1902-07-19	American	http://en.wikipedia.org/wiki/Chet_Miller
734	ball	\N	\N	Bobby	Ball	1925-08-26	American	http://en.wikipedia.org/wiki/Bobby_Ball_(auto_racer)
735	tornaco	\N	\N	Charles	de Tornaco	1927-06-07	Belgian	http://en.wikipedia.org/wiki/Charles_de_Tornaco
736	laurent	\N	\N	Roger	Laurent	1913-02-21	Belgian	http://en.wikipedia.org/wiki/Roger_Laurent
737	obrien	\N	\N	Robert	O'Brien	1908-04-11	American	http://en.wikipedia.org/wiki/Robert_O%27Brien_(auto_racer)
738	gaze	\N	\N	Tony	Gaze	1920-02-03	Australian	http://en.wikipedia.org/wiki/Tony_Gaze
739	charrington	\N	\N	Robin	Montgomerie-Charrington	1915-06-23	British	http://en.wikipedia.org/wiki/Robin_Montgomerie-Charrington
740	comotti	\N	\N	Franco	Comotti	1906-07-24	Italian	http://en.wikipedia.org/wiki/Franco_Comotti
741	etancelin	\N	\N	Philippe	Étancelin	1896-12-28	French	http://en.wikipedia.org/wiki/Philippe_%C3%89tancelin
742	poore	\N	\N	Dennis	Poore	1916-08-19	British	http://en.wikipedia.org/wiki/Dennis_Poore
743	thompson	\N	\N	Eric	Thompson	1919-11-04	British	http://en.wikipedia.org/wiki/Eric_Thompson_(racing_driver)
744	downing	\N	\N	Ken	Downing	1917-12-05	British	http://en.wikipedia.org/wiki/Ken_Downing
745	graham_whitehead	\N	\N	Graham	Whitehead	1922-04-15	British	http://en.wikipedia.org/wiki/Graham_Whitehead
746	bianco	\N	\N	Gino	Bianco	1916-07-22	Brazilian	http://en.wikipedia.org/wiki/Gino_Bianco
747	murray	\N	\N	David	Murray	1909-12-28	British	http://en.wikipedia.org/wiki/David_Murray_(driver)
748	cantoni	\N	\N	Eitel	Cantoni	1906-10-04	Uruguayan	http://en.wikipedia.org/wiki/Eitel_Cantoni
749	aston	\N	\N	Bill	Aston	1900-03-29	British	http://en.wikipedia.org/wiki/Bill_Aston
750	brudes	\N	\N	Adolf	Brudes	1899-10-15	German	http://en.wikipedia.org/wiki/Adolf_Brudes
751	riess	\N	\N	Fritz	Riess	1922-07-11	German	http://en.wikipedia.org/wiki/Fritz_Riess
752	niedermayr	\N	\N	Helmut	Niedermayr	1915-11-29	German	http://en.wikipedia.org/wiki/Helmut_Niedermayr
753	klenk	\N	\N	Hans	Klenk	1919-10-28	German	http://en.wikipedia.org/wiki/Hans_Klenk
754	balsa	\N	\N	Marcel	Balsa	1909-01-01	French	http://en.wikipedia.org/wiki/Marcel_Balsa
755	schoeller	\N	\N	Rudolf	Schoeller	1902-04-27	Swiss	http://en.wikipedia.org/wiki/Rudolf_Schoeller
756	pietsch	\N	\N	Paul	Pietsch	1911-06-20	German	http://en.wikipedia.org/wiki/Paul_Pietsch
757	peters	\N	\N	Josef	Peters	1914-09-16	German	http://en.wikipedia.org/wiki/Josef_Peters_(driver)
758	lof	\N	\N	Dries	van der Lof	1919-08-23	Dutch	http://en.wikipedia.org/wiki/Dries_van_der_Lof
759	flinterman	\N	\N	Jan	Flinterman	1919-10-02	Dutch	http://en.wikipedia.org/wiki/Jan_Flinterman
760	dusio	\N	\N	Piero	Dusio	1899-10-13	Italian	http://en.wikipedia.org/wiki/Piero_Dusio
761	crespo	\N	\N	Alberto	Crespo	1920-01-16	Argentine	http://en.wikipedia.org/wiki/Alberto_Crespo
762	rol	\N	\N	Franco	Rol	1908-06-05	Italian	http://en.wikipedia.org/wiki/Franco_Rol
763	sanesi	\N	\N	Consalvo	Sanesi	1911-03-28	Italian	http://en.wikipedia.org/wiki/Consalvo_Sanesi
764	guy_mairesse	\N	\N	Guy	Mairesse	1910-08-10	French	http://en.wikipedia.org/wiki/Guy_Mairesse
765	louveau	\N	\N	Henri	Louveau	1910-01-25	French	http://en.wikipedia.org/wiki/Henri_Louveau
766	wallard	\N	\N	Lee	Wallard	1910-09-07	American	http://en.wikipedia.org/wiki/Lee_Wallard
767	forberg	\N	\N	Carl	Forberg	1911-03-04	American	http://en.wikipedia.org/wiki/Carl_Forberg
768	rose	\N	\N	Mauri	Rose	1906-05-26	American	http://en.wikipedia.org/wiki/Mauri_Rose
769	mackey	\N	\N	Bill	Mackey	1927-12-15	American	http://en.wikipedia.org/wiki/Bill_Mackey
770	green	\N	\N	Cecil	Green	1919-09-30	American	http://en.wikipedia.org/wiki/Cecil_Green
771	walt_brown	\N	\N	Walt	Brown	1911-12-30	American	http://en.wikipedia.org/wiki/Walt_Brown_(auto_racer)
772	hellings	\N	\N	Mack	Hellings	1915-09-14	American	http://en.wikipedia.org/wiki/Mack_Hellings
773	levegh	\N	\N	Pierre	Levegh	1905-12-22	French	http://en.wikipedia.org/wiki/Pierre_Levegh
774	chaboud	\N	\N	Eugène	Chaboud	1907-04-12	French	http://en.wikipedia.org/wiki/Eug%C3%A8ne_Chaboud
775	gordini	\N	\N	Aldo	Gordini	1921-05-20	French	http://en.wikipedia.org/wiki/Aldo_Gordini
776	kelly	\N	\N	Joe	Kelly	1913-03-13	Irish	http://en.wikipedia.org/wiki/Joe_Kelly_(Formula_One)
777	parker	\N	\N	Philip	Fotheringham-Parker	1907-09-22	British	http://en.wikipedia.org/wiki/Philip_Fotheringham-Parker
778	shawe_taylor	\N	\N	Brian	Shawe Taylor	1915-01-28	British	http://en.wikipedia.org/wiki/Brian_Shawe_Taylor
779	john_james	\N	\N	John	James	1914-05-10	British	http://en.wikipedia.org/wiki/John_James_(auto_racer)
780	branca	\N	\N	Toni	Branca	1916-09-15	Swiss	http://en.wikipedia.org/wiki/Toni_Branca
781	richardson	\N	\N	Ken	Richardson	1911-08-21	British	http://en.wikipedia.org/wiki/Ken_Richardson_(race_car_driver)
782	jover	\N	\N	Juan	Jover	1903-11-23	Spanish	http://en.wikipedia.org/wiki/Juan_Jover
783	grignard	\N	\N	Georges	Grignard	1905-07-25	French	http://en.wikipedia.org/wiki/Georges_Grignard
784	hampshire	\N	\N	David	Hampshire	1917-12-29	British	http://en.wikipedia.org/wiki/David_Hampshire
785	crossley	\N	\N	Geoff	Crossley	1921-05-11	British	http://en.wikipedia.org/wiki/Geoff_Crossley
786	fagioli	\N	\N	Luigi	Fagioli	1898-06-09	Italian	http://en.wikipedia.org/wiki/Luigi_Fagioli
787	harrison	\N	\N	Cuth	Harrison	1906-07-06	British	http://en.wikipedia.org/wiki/Cuth_Harrison
788	fry	\N	\N	Joe	Fry	1915-10-26	British	http://en.wikipedia.org/wiki/Joe_Fry
789	martin	\N	\N	Eugène	Martin	1915-03-24	French	http://en.wikipedia.org/wiki/Eug%C3%A8ne_Martin
790	leslie_johnson	\N	\N	Leslie	Johnson	1912-03-22	British	http://en.wikipedia.org/wiki/Leslie_Johnson_(racing_driver)
791	biondetti	\N	\N	Clemente	Biondetti	1898-08-18	Italian	http://en.wikipedia.org/wiki/Clemente_Biondetti
792	pian	\N	\N	Alfredo	Pián	1912-10-21	Argentine	http://en.wikipedia.org/wiki/Alfredo_Pi%C3%A0n
793	sommer	\N	\N	Raymond	Sommer	1906-08-31	French	http://en.wikipedia.org/wiki/Raymond_Sommer
794	chitwood	\N	\N	Joie	Chitwood	1912-04-14	American	http://en.wikipedia.org/wiki/Joie_Chitwood
795	fohr	\N	\N	Myron	Fohr	1912-06-17	American	http://en.wikipedia.org/wiki/Myron_Fohr
796	ader	\N	\N	Walt	Ader	1913-12-15	American	http://en.wikipedia.org/wiki/Walt_Ader
797	holmes	\N	\N	Jackie	Holmes	1920-09-04	American	http://en.wikipedia.org/wiki/Jackie_Holmes
798	levrett	\N	\N	Bayliss	Levrett	1914-02-14	American	http://en.wikipedia.org/wiki/Bayliss_Levrett
799	jackson	\N	\N	Jimmy	Jackson	1910-07-25	American	http://en.wikipedia.org/wiki/Jimmy_Jackson_(driver)
800	pagani	\N	\N	Nello	Pagani	1911-10-11	Italian	http://en.wikipedia.org/wiki/Nello_Pagani
801	pozzi	\N	\N	Charles	Pozzi	1909-08-27	French	http://en.wikipedia.org/wiki/Charles_Pozzi
802	serafini	\N	\N	Dorino	Serafini	1909-07-22	Italian	http://en.wikipedia.org/wiki/Dorino_Serafini
803	cantrell	\N	\N	Bill	Cantrell	1908-01-31	American	http://en.wikipedia.org/wiki/William_Cantrell
804	mantz	\N	\N	Johnny	Mantz	1918-09-18	American	http://en.wikipedia.org/wiki/Johnny_Mantz
805	kladis	\N	\N	Danny	Kladis	1917-02-10	American	http://en.wikipedia.org/wiki/Danny_Kladis
806	oscar_gonzalez	\N	\N	Óscar	González	1923-11-10	Uruguayan	http://en.wikipedia.org/wiki/Oscar_Gonz%C3%A1lez_(racing_driver)
807	hulkenberg	27	HUL	Nico	Hülkenberg	1987-08-19	German	http://en.wikipedia.org/wiki/Nico_H%C3%BClkenberg
808	petrov	\N	PET	Vitaly	Petrov	1984-09-08	Russian	http://en.wikipedia.org/wiki/Vitaly_Petrov
810	grassi	\N	DIG	Lucas	di Grassi	1984-08-11	Brazilian	http://en.wikipedia.org/wiki/Lucas_di_Grassi
811	bruno_senna	\N	SEN	Bruno	Senna	1983-10-15	Brazilian	http://en.wikipedia.org/wiki/Bruno_Senna
812	chandhok	\N	CHA	Karun	Chandhok	1984-01-19	Indian	http://en.wikipedia.org/wiki/Karun_Chandhok
813	maldonado	13	MAL	Pastor	Maldonado	1985-03-09	Venezuelan	http://en.wikipedia.org/wiki/Pastor_Maldonado
814	resta	\N	DIR	Paul	di Resta	1986-04-16	British	http://en.wikipedia.org/wiki/Paul_di_Resta
815	perez	11	PER	Sergio	Pérez	1990-01-26	Mexican	http://en.wikipedia.org/wiki/Sergio_P%C3%A9rez
816	ambrosio	\N	DAM	Jérôme	d'Ambrosio	1985-12-27	Belgian	http://en.wikipedia.org/wiki/J%C3%A9r%C3%B4me_d%27Ambrosio
817	ricciardo	3	RIC	Daniel	Ricciardo	1989-07-01	Australian	http://en.wikipedia.org/wiki/Daniel_Ricciardo
818	vergne	25	VER	Jean-Éric	Vergne	1990-04-25	French	http://en.wikipedia.org/wiki/Jean-%C3%89ric_Vergne
819	pic	\N	PIC	Charles	Pic	1990-02-15	French	http://en.wikipedia.org/wiki/Charles_Pic
820	chilton	4	CHI	Max	Chilton	1991-04-21	British	http://en.wikipedia.org/wiki/Max_Chilton
821	gutierrez	21	GUT	Esteban	Gutiérrez	1991-08-05	Mexican	http://en.wikipedia.org/wiki/Esteban_Guti%C3%A9rrez
822	bottas	77	BOT	Valtteri	Bottas	1989-08-28	Finnish	http://en.wikipedia.org/wiki/Valtteri_Bottas
823	garde	\N	VDG	Giedo	van der Garde	1985-04-25	Dutch	http://en.wikipedia.org/wiki/Giedo_van_der_Garde
824	jules_bianchi	17	BIA	Jules	Bianchi	1989-08-03	French	http://en.wikipedia.org/wiki/Jules_Bianchi
825	kevin_magnussen	20	MAG	Kevin	Magnussen	1992-10-05	Danish	http://en.wikipedia.org/wiki/Kevin_Magnussen
826	kvyat	26	KVY	Daniil	Kvyat	1994-04-26	Russian	http://en.wikipedia.org/wiki/Daniil_Kvyat
827	lotterer	45	LOT	André	Lotterer	1981-11-19	German	http://en.wikipedia.org/wiki/Andr%C3%A9_Lotterer
828	ericsson	9	ERI	Marcus	Ericsson	1990-09-02	Swedish	http://en.wikipedia.org/wiki/Marcus_Ericsson
829	stevens	28	STE	Will	Stevens	1991-06-28	British	http://en.wikipedia.org/wiki/Will_Stevens
830	max_verstappen	33	VER	Max	Verstappen	1997-09-30	Dutch	http://en.wikipedia.org/wiki/Max_Verstappen
831	nasr	12	NAS	Felipe	Nasr	1992-08-21	Brazilian	http://en.wikipedia.org/wiki/Felipe_Nasr
832	sainz	55	SAI	Carlos	Sainz	1994-09-01	Spanish	http://en.wikipedia.org/wiki/Carlos_Sainz_Jr.
833	merhi	98	MER	Roberto	Merhi	1991-03-22	Spanish	http://en.wikipedia.org/wiki/Roberto_Merhi
834	rossi	53	RSS	Alexander	Rossi	1991-09-25	American	http://en.wikipedia.org/wiki/Alexander_Rossi_%28racing_driver%29
835	jolyon_palmer	30	PAL	Jolyon	Palmer	1991-01-20	British	http://en.wikipedia.org/wiki/Jolyon_Palmer
836	wehrlein	94	WEH	Pascal	Wehrlein	1994-10-18	German	http://en.wikipedia.org/wiki/Pascal_Wehrlein
837	haryanto	88	HAR	Rio	Haryanto	1993-01-22	Indonesian	http://en.wikipedia.org/wiki/Rio_Haryanto
838	vandoorne	2	VAN	Stoffel	Vandoorne	1992-03-26	Belgian	http://en.wikipedia.org/wiki/Stoffel_Vandoorne
839	ocon	31	OCO	Esteban	Ocon	1996-09-17	French	http://en.wikipedia.org/wiki/Esteban_Ocon
840	stroll	18	STR	Lance	Stroll	1998-10-29	Canadian	http://en.wikipedia.org/wiki/Lance_Stroll
841	giovinazzi	99	GIO	Antonio	Giovinazzi	1993-12-14	Italian	http://en.wikipedia.org/wiki/Antonio_Giovinazzi
843	brendon_hartley	28	HAR	Brendon	Hartley	1989-11-10	New Zealander	http://en.wikipedia.org/wiki/Brendon_Hartley
844	leclerc	16	LEC	Charles	Leclerc	1997-10-16	Monegasque	http://en.wikipedia.org/wiki/Charles_Leclerc
845	sirotkin	35	SIR	Sergey	Sirotkin	1995-08-27	Russian	http://en.wikipedia.org/wiki/Sergey_Sirotkin_(racing_driver)
846	norris	4	NOR	Lando	Norris	1999-11-13	British	http://en.wikipedia.org/wiki/Lando_Norris
847	russell	63	RUS	George	Russell	1998-02-15	British	http://en.wikipedia.org/wiki/George_Russell_%28racing_driver%29
848	albon	23	ALB	Alexander	Albon	1996-03-23	Thai	http://en.wikipedia.org/wiki/Alexander_Albon
849	latifi	6	LAT	Nicholas	Latifi	1995-06-29	Canadian	http://en.wikipedia.org/wiki/Nicholas_Latifi
\.


--
-- Data for Name: fact_race_gp; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_race_gp (race_id, year, round, circuit_id, gp_name, date, "time", url) FROM stdin;
1	2009	1	1	Australian Grand Prix	2009-03-29	06:00:00	http://en.wikipedia.org/wiki/2009_Australian_Grand_Prix
2	2009	2	2	Malaysian Grand Prix	2009-04-05	09:00:00	http://en.wikipedia.org/wiki/2009_Malaysian_Grand_Prix
3	2009	3	17	Chinese Grand Prix	2009-04-19	07:00:00	http://en.wikipedia.org/wiki/2009_Chinese_Grand_Prix
4	2009	4	3	Bahrain Grand Prix	2009-04-26	12:00:00	http://en.wikipedia.org/wiki/2009_Bahrain_Grand_Prix
5	2009	5	4	Spanish Grand Prix	2009-05-10	12:00:00	http://en.wikipedia.org/wiki/2009_Spanish_Grand_Prix
6	2009	6	6	Monaco Grand Prix	2009-05-24	12:00:00	http://en.wikipedia.org/wiki/2009_Monaco_Grand_Prix
7	2009	7	5	Turkish Grand Prix	2009-06-07	12:00:00	http://en.wikipedia.org/wiki/2009_Turkish_Grand_Prix
8	2009	8	9	British Grand Prix	2009-06-21	12:00:00	http://en.wikipedia.org/wiki/2009_British_Grand_Prix
9	2009	9	20	German Grand Prix	2009-07-12	12:00:00	http://en.wikipedia.org/wiki/2009_German_Grand_Prix
10	2009	10	11	Hungarian Grand Prix	2009-07-26	12:00:00	http://en.wikipedia.org/wiki/2009_Hungarian_Grand_Prix
11	2009	11	12	European Grand Prix	2009-08-23	12:00:00	http://en.wikipedia.org/wiki/2009_European_Grand_Prix
12	2009	12	13	Belgian Grand Prix	2009-08-30	12:00:00	http://en.wikipedia.org/wiki/2009_Belgian_Grand_Prix
13	2009	13	14	Italian Grand Prix	2009-09-13	12:00:00	http://en.wikipedia.org/wiki/2009_Italian_Grand_Prix
14	2009	14	15	Singapore Grand Prix	2009-09-27	12:00:00	http://en.wikipedia.org/wiki/2009_Singapore_Grand_Prix
15	2009	15	22	Japanese Grand Prix	2009-10-04	05:00:00	http://en.wikipedia.org/wiki/2009_Japanese_Grand_Prix
16	2009	16	18	Brazilian Grand Prix	2009-10-18	16:00:00	http://en.wikipedia.org/wiki/2009_Brazilian_Grand_Prix
17	2009	17	24	Abu Dhabi Grand Prix	2009-11-01	11:00:00	http://en.wikipedia.org/wiki/2009_Abu_Dhabi_Grand_Prix
18	2008	1	1	Australian Grand Prix	2008-03-16	04:30:00	http://en.wikipedia.org/wiki/2008_Australian_Grand_Prix
19	2008	2	2	Malaysian Grand Prix	2008-03-23	07:00:00	http://en.wikipedia.org/wiki/2008_Malaysian_Grand_Prix
20	2008	3	3	Bahrain Grand Prix	2008-04-06	11:30:00	http://en.wikipedia.org/wiki/2008_Bahrain_Grand_Prix
21	2008	4	4	Spanish Grand Prix	2008-04-27	12:00:00	http://en.wikipedia.org/wiki/2008_Spanish_Grand_Prix
22	2008	5	5	Turkish Grand Prix	2008-05-11	12:00:00	http://en.wikipedia.org/wiki/2008_Turkish_Grand_Prix
23	2008	6	6	Monaco Grand Prix	2008-05-25	12:00:00	http://en.wikipedia.org/wiki/2008_Monaco_Grand_Prix
24	2008	7	7	Canadian Grand Prix	2008-06-08	17:00:00	http://en.wikipedia.org/wiki/2008_Canadian_Grand_Prix
25	2008	8	8	French Grand Prix	2008-06-22	12:00:00	http://en.wikipedia.org/wiki/2008_French_Grand_Prix
26	2008	9	9	British Grand Prix	2008-07-06	12:00:00	http://en.wikipedia.org/wiki/2008_British_Grand_Prix
27	2008	10	10	German Grand Prix	2008-07-20	12:00:00	http://en.wikipedia.org/wiki/2008_German_Grand_Prix
28	2008	11	11	Hungarian Grand Prix	2008-08-03	12:00:00	http://en.wikipedia.org/wiki/2008_Hungarian_Grand_Prix
29	2008	12	12	European Grand Prix	2008-08-24	12:00:00	http://en.wikipedia.org/wiki/2008_European_Grand_Prix
30	2008	13	13	Belgian Grand Prix	2008-09-07	12:00:00	http://en.wikipedia.org/wiki/2008_Belgian_Grand_Prix
31	2008	14	14	Italian Grand Prix	2008-09-14	12:00:00	http://en.wikipedia.org/wiki/2008_Italian_Grand_Prix
32	2008	15	15	Singapore Grand Prix	2008-09-28	12:00:00	http://en.wikipedia.org/wiki/2008_Singapore_Grand_Prix
33	2008	16	16	Japanese Grand Prix	2008-10-12	04:30:00	http://en.wikipedia.org/wiki/2008_Japanese_Grand_Prix
34	2008	17	17	Chinese Grand Prix	2008-10-19	07:00:00	http://en.wikipedia.org/wiki/2008_Chinese_Grand_Prix
35	2008	18	18	Brazilian Grand Prix	2008-11-02	17:00:00	http://en.wikipedia.org/wiki/2008_Brazilian_Grand_Prix
36	2007	1	1	Australian Grand Prix	2007-03-18	03:00:00	http://en.wikipedia.org/wiki/2007_Australian_Grand_Prix
37	2007	2	2	Malaysian Grand Prix	2007-04-08	07:00:00	http://en.wikipedia.org/wiki/2007_Malaysian_Grand_Prix
38	2007	3	3	Bahrain Grand Prix	2007-04-15	11:30:00	http://en.wikipedia.org/wiki/2007_Bahrain_Grand_Prix
39	2007	4	4	Spanish Grand Prix	2007-05-13	12:00:00	http://en.wikipedia.org/wiki/2007_Spanish_Grand_Prix
40	2007	5	6	Monaco Grand Prix	2007-05-27	12:00:00	http://en.wikipedia.org/wiki/2007_Monaco_Grand_Prix
41	2007	6	7	Canadian Grand Prix	2007-06-10	17:00:00	http://en.wikipedia.org/wiki/2007_Canadian_Grand_Prix
42	2007	7	19	United States Grand Prix	2007-06-17	17:00:00	http://en.wikipedia.org/wiki/2007_United_States_Grand_Prix
43	2007	8	8	French Grand Prix	2007-07-01	12:00:00	http://en.wikipedia.org/wiki/2007_French_Grand_Prix
44	2007	9	9	British Grand Prix	2007-07-08	12:00:00	http://en.wikipedia.org/wiki/2007_British_Grand_Prix
45	2007	10	20	European Grand Prix	2007-07-22	12:00:00	http://en.wikipedia.org/wiki/2007_European_Grand_Prix
46	2007	11	11	Hungarian Grand Prix	2007-08-05	12:00:00	http://en.wikipedia.org/wiki/2007_Hungarian_Grand_Prix
47	2007	12	5	Turkish Grand Prix	2007-08-26	12:00:00	http://en.wikipedia.org/wiki/2007_Turkish_Grand_Prix
48	2007	13	14	Italian Grand Prix	2007-09-09	12:00:00	http://en.wikipedia.org/wiki/2007_Italian_Grand_Prix
49	2007	14	13	Belgian Grand Prix	2007-09-16	12:00:00	http://en.wikipedia.org/wiki/2007_Belgian_Grand_Prix
50	2007	15	16	Japanese Grand Prix	2007-09-30	04:30:00	http://en.wikipedia.org/wiki/2007_Japanese_Grand_Prix
51	2007	16	17	Chinese Grand Prix	2007-10-07	06:00:00	http://en.wikipedia.org/wiki/2007_Chinese_Grand_Prix
52	2007	17	18	Brazilian Grand Prix	2007-10-21	16:00:00	http://en.wikipedia.org/wiki/2007_Brazilian_Grand_Prix
53	2006	1	3	Bahrain Grand Prix	2006-03-12	14:30:00	http://en.wikipedia.org/wiki/2006_Bahrain_Grand_Prix
54	2006	2	2	Malaysian Grand Prix	2006-03-19	15:00:00	http://en.wikipedia.org/wiki/2006_Malaysian_Grand_Prix
55	2006	3	1	Australian Grand Prix	2006-04-02	14:00:00	http://en.wikipedia.org/wiki/2006_Australian_Grand_Prix
56	2006	4	21	San Marino Grand Prix	2006-04-23	14:00:00	http://en.wikipedia.org/wiki/2006_San_Marino_Grand_Prix
57	2006	5	20	European Grand Prix	2006-05-07	14:00:00	http://en.wikipedia.org/wiki/2006_European_Grand_Prix
58	2006	6	4	Spanish Grand Prix	2006-05-14	14:00:00	http://en.wikipedia.org/wiki/2006_Spanish_Grand_Prix
59	2006	7	6	Monaco Grand Prix	2006-05-28	14:00:00	http://en.wikipedia.org/wiki/2006_Monaco_Grand_Prix
60	2006	8	9	British Grand Prix	2006-06-11	12:00:00	http://en.wikipedia.org/wiki/2006_British_Grand_Prix
61	2006	9	7	Canadian Grand Prix	2006-06-25	13:00:00	http://en.wikipedia.org/wiki/2006_Canadian_Grand_Prix
62	2006	10	19	United States Grand Prix	2006-07-02	14:00:00	http://en.wikipedia.org/wiki/2006_United_States_Grand_Prix
63	2006	11	8	French Grand Prix	2006-07-16	14:00:00	http://en.wikipedia.org/wiki/2006_French_Grand_Prix
64	2006	12	10	German Grand Prix	2006-07-30	14:00:00	http://en.wikipedia.org/wiki/2006_German_Grand_Prix
65	2006	13	11	Hungarian Grand Prix	2006-08-06	14:00:00	http://en.wikipedia.org/wiki/2006_Hungarian_Grand_Prix
66	2006	14	5	Turkish Grand Prix	2006-08-27	15:00:00	http://en.wikipedia.org/wiki/2006_Turkish_Grand_Prix
67	2006	15	14	Italian Grand Prix	2006-09-10	14:00:00	http://en.wikipedia.org/wiki/2006_Italian_Grand_Prix
68	2006	16	17	Chinese Grand Prix	2006-10-01	14:00:00	http://en.wikipedia.org/wiki/2006_Chinese_Grand_Prix
69	2006	17	22	Japanese Grand Prix	2006-10-08	14:00:00	http://en.wikipedia.org/wiki/2006_Japanese_Grand_Prix
70	2006	18	18	Brazilian Grand Prix	2006-10-22	14:00:00	http://en.wikipedia.org/wiki/2006_Brazilian_Grand_Prix
71	2005	1	1	Australian Grand Prix	2005-03-06	14:00:00	http://en.wikipedia.org/wiki/2005_Australian_Grand_Prix
72	2005	2	2	Malaysian Grand Prix	2005-03-20	15:00:00	http://en.wikipedia.org/wiki/2005_Malaysian_Grand_Prix
73	2005	3	3	Bahrain Grand Prix	2005-04-03	14:30:00	http://en.wikipedia.org/wiki/2005_Bahrain_Grand_Prix
74	2005	4	21	San Marino Grand Prix	2005-04-24	14:00:00	http://en.wikipedia.org/wiki/2005_San_Marino_Grand_Prix
75	2005	5	4	Spanish Grand Prix	2005-05-08	14:00:00	http://en.wikipedia.org/wiki/2005_Spanish_Grand_Prix
76	2005	6	6	Monaco Grand Prix	2005-05-22	14:00:00	http://en.wikipedia.org/wiki/2005_Monaco_Grand_Prix
77	2005	7	20	European Grand Prix	2005-05-29	14:00:00	http://en.wikipedia.org/wiki/2005_European_Grand_Prix
78	2005	8	7	Canadian Grand Prix	2005-06-12	13:00:00	http://en.wikipedia.org/wiki/2005_Canadian_Grand_Prix
79	2005	9	19	United States Grand Prix	2005-06-19	14:00:00	http://en.wikipedia.org/wiki/2005_United_States_Grand_Prix
80	2005	10	8	French Grand Prix	2005-07-03	14:00:00	http://en.wikipedia.org/wiki/2005_French_Grand_Prix
81	2005	11	9	British Grand Prix	2005-07-10	14:00:00	http://en.wikipedia.org/wiki/2005_British_Grand_Prix
82	2005	12	10	German Grand Prix	2005-07-24	14:00:00	http://en.wikipedia.org/wiki/2005_German_Grand_Prix
83	2005	13	11	Hungarian Grand Prix	2005-07-31	14:00:00	http://en.wikipedia.org/wiki/2005_Hungarian_Grand_Prix
84	2005	14	5	Turkish Grand Prix	2005-08-21	15:00:00	http://en.wikipedia.org/wiki/2005_Turkish_Grand_Prix
85	2005	15	14	Italian Grand Prix	2005-09-04	14:00:00	http://en.wikipedia.org/wiki/2005_Italian_Grand_Prix
86	2005	16	13	Belgian Grand Prix	2005-09-11	14:00:00	http://en.wikipedia.org/wiki/2005_Belgian_Grand_Prix
87	2005	17	18	Brazilian Grand Prix	2005-09-25	14:00:00	http://en.wikipedia.org/wiki/2005_Brazilian_Grand_Prix
88	2005	18	22	Japanese Grand Prix	2005-10-09	14:00:00	http://en.wikipedia.org/wiki/2005_Japanese_Grand_Prix
89	2005	19	17	Chinese Grand Prix	2005-10-16	14:00:00	http://en.wikipedia.org/wiki/2005_Chinese_Grand_Prix
90	2004	1	1	Australian Grand Prix	2004-03-07	\N	http://en.wikipedia.org/wiki/2004_Australian_Grand_Prix
91	2004	2	2	Malaysian Grand Prix	2004-03-21	\N	http://en.wikipedia.org/wiki/2004_Malaysian_Grand_Prix
92	2004	3	3	Bahrain Grand Prix	2004-04-04	\N	http://en.wikipedia.org/wiki/2004_Bahrain_Grand_Prix
93	2004	4	21	San Marino Grand Prix	2004-04-25	\N	http://en.wikipedia.org/wiki/2004_San_Marino_Grand_Prix
94	2004	5	4	Spanish Grand Prix	2004-05-09	\N	http://en.wikipedia.org/wiki/2004_Spanish_Grand_Prix
95	2004	6	6	Monaco Grand Prix	2004-05-23	\N	http://en.wikipedia.org/wiki/2004_Monaco_Grand_Prix
96	2004	7	20	European Grand Prix	2004-05-30	\N	http://en.wikipedia.org/wiki/2004_European_Grand_Prix
97	2004	8	7	Canadian Grand Prix	2004-06-13	\N	http://en.wikipedia.org/wiki/2004_Canadian_Grand_Prix
98	2004	9	19	United States Grand Prix	2004-06-20	\N	http://en.wikipedia.org/wiki/2004_United_States_Grand_Prix
99	2004	10	8	French Grand Prix	2004-07-04	\N	http://en.wikipedia.org/wiki/2004_French_Grand_Prix
100	2004	11	9	British Grand Prix	2004-07-11	\N	http://en.wikipedia.org/wiki/2004_British_Grand_Prix
101	2004	12	10	German Grand Prix	2004-07-25	\N	http://en.wikipedia.org/wiki/2004_German_Grand_Prix
102	2004	13	11	Hungarian Grand Prix	2004-08-15	\N	http://en.wikipedia.org/wiki/2004_Hungarian_Grand_Prix
103	2004	14	13	Belgian Grand Prix	2004-08-29	\N	http://en.wikipedia.org/wiki/2004_Belgian_Grand_Prix
104	2004	15	14	Italian Grand Prix	2004-09-12	\N	http://en.wikipedia.org/wiki/2004_Italian_Grand_Prix
105	2004	16	17	Chinese Grand Prix	2004-09-26	\N	http://en.wikipedia.org/wiki/2004_Chinese_Grand_Prix
106	2004	17	22	Japanese Grand Prix	2004-10-10	\N	http://en.wikipedia.org/wiki/2004_Japanese_Grand_Prix
107	2004	18	18	Brazilian Grand Prix	2004-10-24	\N	http://en.wikipedia.org/wiki/2004_Brazilian_Grand_Prix
108	2003	1	1	Australian Grand Prix	2003-03-09	\N	http://en.wikipedia.org/wiki/2003_Australian_Grand_Prix
109	2003	2	2	Malaysian Grand Prix	2003-03-23	\N	http://en.wikipedia.org/wiki/2003_Malaysian_Grand_Prix
110	2003	3	18	Brazilian Grand Prix	2003-04-06	\N	http://en.wikipedia.org/wiki/2003_Brazilian_Grand_Prix
111	2003	4	21	San Marino Grand Prix	2003-04-20	\N	http://en.wikipedia.org/wiki/2003_San_Marino_Grand_Prix
112	2003	5	4	Spanish Grand Prix	2003-05-04	\N	http://en.wikipedia.org/wiki/2003_Spanish_Grand_Prix
113	2003	6	23	Austrian Grand Prix	2003-05-18	\N	http://en.wikipedia.org/wiki/2003_Austrian_Grand_Prix
114	2003	7	6	Monaco Grand Prix	2003-06-01	\N	http://en.wikipedia.org/wiki/2003_Monaco_Grand_Prix
115	2003	8	7	Canadian Grand Prix	2003-06-15	\N	http://en.wikipedia.org/wiki/2003_Canadian_Grand_Prix
116	2003	9	20	European Grand Prix	2003-06-29	\N	http://en.wikipedia.org/wiki/2003_European_Grand_Prix
117	2003	10	8	French Grand Prix	2003-07-06	\N	http://en.wikipedia.org/wiki/2003_French_Grand_Prix
118	2003	11	9	British Grand Prix	2003-07-20	\N	http://en.wikipedia.org/wiki/2003_British_Grand_Prix
119	2003	12	10	German Grand Prix	2003-08-03	\N	http://en.wikipedia.org/wiki/2003_German_Grand_Prix
120	2003	13	11	Hungarian Grand Prix	2003-08-24	\N	http://en.wikipedia.org/wiki/2003_Hungarian_Grand_Prix
121	2003	14	14	Italian Grand Prix	2003-09-14	\N	http://en.wikipedia.org/wiki/2003_Italian_Grand_Prix
122	2003	15	19	United States Grand Prix	2003-09-28	\N	http://en.wikipedia.org/wiki/2003_United_States_Grand_Prix
123	2003	16	22	Japanese Grand Prix	2003-10-12	\N	http://en.wikipedia.org/wiki/2003_Japanese_Grand_Prix
124	2002	1	1	Australian Grand Prix	2002-03-03	\N	http://en.wikipedia.org/wiki/2002_Australian_Grand_Prix
125	2002	2	2	Malaysian Grand Prix	2002-03-17	\N	http://en.wikipedia.org/wiki/2002_Malaysian_Grand_Prix
126	2002	3	18	Brazilian Grand Prix	2002-03-31	\N	http://en.wikipedia.org/wiki/2002_Brazilian_Grand_Prix
127	2002	4	21	San Marino Grand Prix	2002-04-14	\N	http://en.wikipedia.org/wiki/2002_San_Marino_Grand_Prix
128	2002	5	4	Spanish Grand Prix	2002-04-28	\N	http://en.wikipedia.org/wiki/2002_Spanish_Grand_Prix
129	2002	6	23	Austrian Grand Prix	2002-05-12	\N	http://en.wikipedia.org/wiki/2002_Austrian_Grand_Prix
130	2002	7	6	Monaco Grand Prix	2002-05-26	\N	http://en.wikipedia.org/wiki/2002_Monaco_Grand_Prix
131	2002	8	7	Canadian Grand Prix	2002-06-09	\N	http://en.wikipedia.org/wiki/2002_Canadian_Grand_Prix
132	2002	9	20	European Grand Prix	2002-06-23	\N	http://en.wikipedia.org/wiki/2002_European_Grand_Prix
133	2002	10	9	British Grand Prix	2002-07-07	\N	http://en.wikipedia.org/wiki/2002_British_Grand_Prix
134	2002	11	8	French Grand Prix	2002-07-21	\N	http://en.wikipedia.org/wiki/2002_French_Grand_Prix
135	2002	12	10	German Grand Prix	2002-07-28	\N	http://en.wikipedia.org/wiki/2002_German_Grand_Prix
136	2002	13	11	Hungarian Grand Prix	2002-08-18	\N	http://en.wikipedia.org/wiki/2002_Hungarian_Grand_Prix
137	2002	14	13	Belgian Grand Prix	2002-09-01	\N	http://en.wikipedia.org/wiki/2002_Belgian_Grand_Prix
138	2002	15	14	Italian Grand Prix	2002-09-15	\N	http://en.wikipedia.org/wiki/2002_Italian_Grand_Prix
139	2002	16	19	United States Grand Prix	2002-09-29	\N	http://en.wikipedia.org/wiki/2002_United_States_Grand_Prix
140	2002	17	22	Japanese Grand Prix	2002-10-13	\N	http://en.wikipedia.org/wiki/2002_Japanese_Grand_Prix
141	2001	1	1	Australian Grand Prix	2001-03-04	\N	http://en.wikipedia.org/wiki/2001_Australian_Grand_Prix
142	2001	2	2	Malaysian Grand Prix	2001-03-18	\N	http://en.wikipedia.org/wiki/2001_Malaysian_Grand_Prix
143	2001	3	18	Brazilian Grand Prix	2001-04-01	\N	http://en.wikipedia.org/wiki/2001_Brazilian_Grand_Prix
144	2001	4	21	San Marino Grand Prix	2001-04-15	\N	http://en.wikipedia.org/wiki/2001_San_Marino_Grand_Prix
145	2001	5	4	Spanish Grand Prix	2001-04-29	\N	http://en.wikipedia.org/wiki/2001_Spanish_Grand_Prix
146	2001	6	23	Austrian Grand Prix	2001-05-13	\N	http://en.wikipedia.org/wiki/2001_Austrian_Grand_Prix
147	2001	7	6	Monaco Grand Prix	2001-05-27	\N	http://en.wikipedia.org/wiki/2001_Monaco_Grand_Prix
148	2001	8	7	Canadian Grand Prix	2001-06-10	\N	http://en.wikipedia.org/wiki/2001_Canadian_Grand_Prix
149	2001	9	20	European Grand Prix	2001-06-24	\N	http://en.wikipedia.org/wiki/2001_European_Grand_Prix
150	2001	10	8	French Grand Prix	2001-07-01	\N	http://en.wikipedia.org/wiki/2001_French_Grand_Prix
151	2001	11	9	British Grand Prix	2001-07-15	\N	http://en.wikipedia.org/wiki/2001_British_Grand_Prix
152	2001	12	10	German Grand Prix	2001-07-29	\N	http://en.wikipedia.org/wiki/2001_German_Grand_Prix
153	2001	13	11	Hungarian Grand Prix	2001-08-19	\N	http://en.wikipedia.org/wiki/2001_Hungarian_Grand_Prix
154	2001	14	13	Belgian Grand Prix	2001-09-02	\N	http://en.wikipedia.org/wiki/2001_Belgian_Grand_Prix
155	2001	15	14	Italian Grand Prix	2001-09-16	\N	http://en.wikipedia.org/wiki/2001_Italian_Grand_Prix
156	2001	16	19	United States Grand Prix	2001-09-30	\N	http://en.wikipedia.org/wiki/2001_United_States_Grand_Prix
157	2001	17	22	Japanese Grand Prix	2001-10-14	\N	http://en.wikipedia.org/wiki/2001_Japanese_Grand_Prix
158	2000	1	1	Australian Grand Prix	2000-03-12	\N	http://en.wikipedia.org/wiki/2000_Australian_Grand_Prix
159	2000	2	18	Brazilian Grand Prix	2000-03-26	\N	http://en.wikipedia.org/wiki/2000_Brazilian_Grand_Prix
160	2000	3	21	San Marino Grand Prix	2000-04-09	\N	http://en.wikipedia.org/wiki/2000_San_Marino_Grand_Prix
161	2000	4	9	British Grand Prix	2000-04-23	\N	http://en.wikipedia.org/wiki/2000_British_Grand_Prix
162	2000	5	4	Spanish Grand Prix	2000-05-07	\N	http://en.wikipedia.org/wiki/2000_Spanish_Grand_Prix
163	2000	6	20	European Grand Prix	2000-05-21	\N	http://en.wikipedia.org/wiki/2000_European_Grand_Prix
164	2000	7	6	Monaco Grand Prix	2000-06-04	\N	http://en.wikipedia.org/wiki/2000_Monaco_Grand_Prix
165	2000	8	7	Canadian Grand Prix	2000-06-18	\N	http://en.wikipedia.org/wiki/2000_Canadian_Grand_Prix
166	2000	9	8	French Grand Prix	2000-07-02	\N	http://en.wikipedia.org/wiki/2000_French_Grand_Prix
167	2000	10	23	Austrian Grand Prix	2000-07-16	\N	http://en.wikipedia.org/wiki/2000_Austrian_Grand_Prix
168	2000	11	10	German Grand Prix	2000-07-30	\N	http://en.wikipedia.org/wiki/2000_German_Grand_Prix
169	2000	12	11	Hungarian Grand Prix	2000-08-13	\N	http://en.wikipedia.org/wiki/2000_Hungarian_Grand_Prix
170	2000	13	13	Belgian Grand Prix	2000-08-27	\N	http://en.wikipedia.org/wiki/2000_Belgian_Grand_Prix
171	2000	14	14	Italian Grand Prix	2000-09-10	\N	http://en.wikipedia.org/wiki/2000_Italian_Grand_Prix
172	2000	15	19	United States Grand Prix	2000-09-24	\N	http://en.wikipedia.org/wiki/2000_United_States_Grand_Prix
173	2000	16	22	Japanese Grand Prix	2000-10-08	\N	http://en.wikipedia.org/wiki/2000_Japanese_Grand_Prix
174	2000	17	2	Malaysian Grand Prix	2000-10-22	\N	http://en.wikipedia.org/wiki/2000_Malaysian_Grand_Prix
175	1999	1	1	Australian Grand Prix	1999-03-07	\N	http://en.wikipedia.org/wiki/1999_Australian_Grand_Prix
176	1999	2	18	Brazilian Grand Prix	1999-04-11	\N	http://en.wikipedia.org/wiki/1999_Brazilian_Grand_Prix
177	1999	3	21	San Marino Grand Prix	1999-05-02	\N	http://en.wikipedia.org/wiki/1999_San_Marino_Grand_Prix
178	1999	4	6	Monaco Grand Prix	1999-05-16	\N	http://en.wikipedia.org/wiki/1999_Monaco_Grand_Prix
179	1999	5	4	Spanish Grand Prix	1999-05-30	\N	http://en.wikipedia.org/wiki/1999_Spanish_Grand_Prix
180	1999	6	7	Canadian Grand Prix	1999-06-13	\N	http://en.wikipedia.org/wiki/1999_Canadian_Grand_Prix
181	1999	7	8	French Grand Prix	1999-06-27	\N	http://en.wikipedia.org/wiki/1999_French_Grand_Prix
182	1999	8	9	British Grand Prix	1999-07-11	\N	http://en.wikipedia.org/wiki/1999_British_Grand_Prix
183	1999	9	23	Austrian Grand Prix	1999-07-25	\N	http://en.wikipedia.org/wiki/1999_Austrian_Grand_Prix
184	1999	10	10	German Grand Prix	1999-08-01	\N	http://en.wikipedia.org/wiki/1999_German_Grand_Prix
185	1999	11	11	Hungarian Grand Prix	1999-08-15	\N	http://en.wikipedia.org/wiki/1999_Hungarian_Grand_Prix
186	1999	12	13	Belgian Grand Prix	1999-08-29	\N	http://en.wikipedia.org/wiki/1999_Belgian_Grand_Prix
187	1999	13	14	Italian Grand Prix	1999-09-12	\N	http://en.wikipedia.org/wiki/1999_Italian_Grand_Prix
188	1999	14	20	European Grand Prix	1999-09-26	\N	http://en.wikipedia.org/wiki/1999_European_Grand_Prix
189	1999	15	2	Malaysian Grand Prix	1999-10-17	\N	http://en.wikipedia.org/wiki/1999_Malaysian_Grand_Prix
190	1999	16	22	Japanese Grand Prix	1999-10-31	\N	http://en.wikipedia.org/wiki/1999_Japanese_Grand_Prix
191	1998	1	1	Australian Grand Prix	1998-03-08	\N	http://en.wikipedia.org/wiki/1998_Australian_Grand_Prix
192	1998	2	18	Brazilian Grand Prix	1998-03-29	\N	http://en.wikipedia.org/wiki/1998_Brazilian_Grand_Prix
193	1998	3	25	Argentine Grand Prix	1998-04-12	\N	http://en.wikipedia.org/wiki/1998_Argentine_Grand_Prix
194	1998	4	21	San Marino Grand Prix	1998-04-26	\N	http://en.wikipedia.org/wiki/1998_San_Marino_Grand_Prix
195	1998	5	4	Spanish Grand Prix	1998-05-10	\N	http://en.wikipedia.org/wiki/1998_Spanish_Grand_Prix
196	1998	6	6	Monaco Grand Prix	1998-05-24	\N	http://en.wikipedia.org/wiki/1998_Monaco_Grand_Prix
197	1998	7	7	Canadian Grand Prix	1998-06-07	\N	http://en.wikipedia.org/wiki/1998_Canadian_Grand_Prix
198	1998	8	8	French Grand Prix	1998-06-28	\N	http://en.wikipedia.org/wiki/1998_French_Grand_Prix
199	1998	9	9	British Grand Prix	1998-07-12	\N	http://en.wikipedia.org/wiki/1998_British_Grand_Prix
200	1998	10	23	Austrian Grand Prix	1998-07-26	\N	http://en.wikipedia.org/wiki/1998_Austrian_Grand_Prix
201	1998	11	10	German Grand Prix	1998-08-02	\N	http://en.wikipedia.org/wiki/1998_German_Grand_Prix
202	1998	12	11	Hungarian Grand Prix	1998-08-16	\N	http://en.wikipedia.org/wiki/1998_Hungarian_Grand_Prix
203	1998	13	13	Belgian Grand Prix	1998-08-30	\N	http://en.wikipedia.org/wiki/1998_Belgian_Grand_Prix
204	1998	14	14	Italian Grand Prix	1998-09-13	\N	http://en.wikipedia.org/wiki/1998_Italian_Grand_Prix
205	1998	15	20	Luxembourg Grand Prix	1998-09-27	\N	http://en.wikipedia.org/wiki/1998_Luxembourg_Grand_Prix
206	1998	16	22	Japanese Grand Prix	1998-11-01	\N	http://en.wikipedia.org/wiki/1998_Japanese_Grand_Prix
207	1997	1	1	Australian Grand Prix	1997-03-09	\N	http://en.wikipedia.org/wiki/1997_Australian_Grand_Prix
208	1997	2	18	Brazilian Grand Prix	1997-03-30	\N	http://en.wikipedia.org/wiki/1997_Brazilian_Grand_Prix
209	1997	3	25	Argentine Grand Prix	1997-04-13	\N	http://en.wikipedia.org/wiki/1997_Argentine_Grand_Prix
210	1997	4	21	San Marino Grand Prix	1997-04-27	\N	http://en.wikipedia.org/wiki/1997_San_Marino_Grand_Prix
211	1997	5	6	Monaco Grand Prix	1997-05-11	\N	http://en.wikipedia.org/wiki/1997_Monaco_Grand_Prix
212	1997	6	4	Spanish Grand Prix	1997-05-25	\N	http://en.wikipedia.org/wiki/1997_Spanish_Grand_Prix
213	1997	7	7	Canadian Grand Prix	1997-06-15	\N	http://en.wikipedia.org/wiki/1997_Canadian_Grand_Prix
214	1997	8	8	French Grand Prix	1997-06-29	\N	http://en.wikipedia.org/wiki/1997_French_Grand_Prix
215	1997	9	9	British Grand Prix	1997-07-13	\N	http://en.wikipedia.org/wiki/1997_British_Grand_Prix
216	1997	10	10	German Grand Prix	1997-07-27	\N	http://en.wikipedia.org/wiki/1997_German_Grand_Prix
217	1997	11	11	Hungarian Grand Prix	1997-08-10	\N	http://en.wikipedia.org/wiki/1997_Hungarian_Grand_Prix
218	1997	12	13	Belgian Grand Prix	1997-08-24	\N	http://en.wikipedia.org/wiki/1997_Belgian_Grand_Prix
219	1997	13	14	Italian Grand Prix	1997-09-07	\N	http://en.wikipedia.org/wiki/1997_Italian_Grand_Prix
220	1997	14	23	Austrian Grand Prix	1997-09-21	\N	http://en.wikipedia.org/wiki/1997_Austrian_Grand_Prix
221	1997	15	20	Luxembourg Grand Prix	1997-09-28	\N	http://en.wikipedia.org/wiki/1997_Luxembourg_Grand_Prix
222	1997	16	22	Japanese Grand Prix	1997-10-12	\N	http://en.wikipedia.org/wiki/1997_Japanese_Grand_Prix
223	1997	17	26	European Grand Prix	1997-10-26	\N	http://en.wikipedia.org/wiki/1997_European_Grand_Prix
224	1996	1	1	Australian Grand Prix	1996-03-10	\N	http://en.wikipedia.org/wiki/1996_Australian_Grand_Prix
225	1996	2	18	Brazilian Grand Prix	1996-03-31	\N	http://en.wikipedia.org/wiki/1996_Brazilian_Grand_Prix
226	1996	3	25	Argentine Grand Prix	1996-04-07	\N	http://en.wikipedia.org/wiki/1996_Argentine_Grand_Prix
227	1996	4	20	European Grand Prix	1996-04-28	\N	http://en.wikipedia.org/wiki/1996_European_Grand_Prix
228	1996	5	21	San Marino Grand Prix	1996-05-05	\N	http://en.wikipedia.org/wiki/1996_San_Marino_Grand_Prix
229	1996	6	6	Monaco Grand Prix	1996-05-19	\N	http://en.wikipedia.org/wiki/1996_Monaco_Grand_Prix
230	1996	7	4	Spanish Grand Prix	1996-06-02	\N	http://en.wikipedia.org/wiki/1996_Spanish_Grand_Prix
231	1996	8	7	Canadian Grand Prix	1996-06-16	\N	http://en.wikipedia.org/wiki/1996_Canadian_Grand_Prix
232	1996	9	8	French Grand Prix	1996-06-30	\N	http://en.wikipedia.org/wiki/1996_French_Grand_Prix
233	1996	10	9	British Grand Prix	1996-07-14	\N	http://en.wikipedia.org/wiki/1996_British_Grand_Prix
234	1996	11	10	German Grand Prix	1996-07-28	\N	http://en.wikipedia.org/wiki/1996_German_Grand_Prix
235	1996	12	11	Hungarian Grand Prix	1996-08-11	\N	http://en.wikipedia.org/wiki/1996_Hungarian_Grand_Prix
236	1996	13	13	Belgian Grand Prix	1996-08-25	\N	http://en.wikipedia.org/wiki/1996_Belgian_Grand_Prix
237	1996	14	14	Italian Grand Prix	1996-09-08	\N	http://en.wikipedia.org/wiki/1996_Italian_Grand_Prix
238	1996	15	27	Portuguese Grand Prix	1996-09-22	\N	http://en.wikipedia.org/wiki/1996_Portuguese_Grand_Prix
239	1996	16	22	Japanese Grand Prix	1996-10-13	\N	http://en.wikipedia.org/wiki/1996_Japanese_Grand_Prix
240	1995	1	18	Brazilian Grand Prix	1995-03-26	\N	http://en.wikipedia.org/wiki/1995_Brazilian_Grand_Prix
241	1995	2	25	Argentine Grand Prix	1995-04-09	\N	http://en.wikipedia.org/wiki/1995_Argentine_Grand_Prix
242	1995	3	21	San Marino Grand Prix	1995-04-30	\N	http://en.wikipedia.org/wiki/1995_San_Marino_Grand_Prix
243	1995	4	4	Spanish Grand Prix	1995-05-14	\N	http://en.wikipedia.org/wiki/1995_Spanish_Grand_Prix
244	1995	5	6	Monaco Grand Prix	1995-05-28	\N	http://en.wikipedia.org/wiki/1995_Monaco_Grand_Prix
245	1995	6	7	Canadian Grand Prix	1995-06-11	\N	http://en.wikipedia.org/wiki/1995_Canadian_Grand_Prix
246	1995	7	8	French Grand Prix	1995-07-02	\N	http://en.wikipedia.org/wiki/1995_French_Grand_Prix
247	1995	8	9	British Grand Prix	1995-07-16	\N	http://en.wikipedia.org/wiki/1995_British_Grand_Prix
248	1995	9	10	German Grand Prix	1995-07-30	\N	http://en.wikipedia.org/wiki/1995_German_Grand_Prix
249	1995	10	11	Hungarian Grand Prix	1995-08-13	\N	http://en.wikipedia.org/wiki/1995_Hungarian_Grand_Prix
250	1995	11	13	Belgian Grand Prix	1995-08-27	\N	http://en.wikipedia.org/wiki/1995_Belgian_Grand_Prix
251	1995	12	14	Italian Grand Prix	1995-09-10	\N	http://en.wikipedia.org/wiki/1995_Italian_Grand_Prix
252	1995	13	27	Portuguese Grand Prix	1995-09-24	\N	http://en.wikipedia.org/wiki/1995_Portuguese_Grand_Prix
253	1995	14	20	European Grand Prix	1995-10-01	\N	http://en.wikipedia.org/wiki/1995_European_Grand_Prix
254	1995	15	28	Pacific Grand Prix	1995-10-22	\N	http://en.wikipedia.org/wiki/1995_Pacific_Grand_Prix
255	1995	16	22	Japanese Grand Prix	1995-10-29	\N	http://en.wikipedia.org/wiki/1995_Japanese_Grand_Prix
256	1995	17	29	Australian Grand Prix	1995-11-12	\N	http://en.wikipedia.org/wiki/1995_Australian_Grand_Prix
257	1994	1	18	Brazilian Grand Prix	1994-03-27	\N	http://en.wikipedia.org/wiki/1994_Brazilian_Grand_Prix
258	1994	2	28	Pacific Grand Prix	1994-04-17	\N	http://en.wikipedia.org/wiki/1994_Pacific_Grand_Prix
259	1994	3	21	San Marino Grand Prix	1994-05-01	\N	http://en.wikipedia.org/wiki/1994_San_Marino_Grand_Prix
260	1994	4	6	Monaco Grand Prix	1994-05-15	\N	http://en.wikipedia.org/wiki/1994_Monaco_Grand_Prix
261	1994	5	4	Spanish Grand Prix	1994-05-29	\N	http://en.wikipedia.org/wiki/1994_Spanish_Grand_Prix
262	1994	6	7	Canadian Grand Prix	1994-06-12	\N	http://en.wikipedia.org/wiki/1994_Canadian_Grand_Prix
263	1994	7	8	French Grand Prix	1994-07-03	\N	http://en.wikipedia.org/wiki/1994_French_Grand_Prix
264	1994	8	9	British Grand Prix	1994-07-10	\N	http://en.wikipedia.org/wiki/1994_British_Grand_Prix
265	1994	9	10	German Grand Prix	1994-07-31	\N	http://en.wikipedia.org/wiki/1994_German_Grand_Prix
266	1994	10	11	Hungarian Grand Prix	1994-08-14	\N	http://en.wikipedia.org/wiki/1994_Hungarian_Grand_Prix
267	1994	11	13	Belgian Grand Prix	1994-08-28	\N	http://en.wikipedia.org/wiki/1994_Belgian_Grand_Prix
268	1994	12	14	Italian Grand Prix	1994-09-11	\N	http://en.wikipedia.org/wiki/1994_Italian_Grand_Prix
269	1994	13	27	Portuguese Grand Prix	1994-09-25	\N	http://en.wikipedia.org/wiki/1994_Portuguese_Grand_Prix
270	1994	14	26	European Grand Prix	1994-10-16	\N	http://en.wikipedia.org/wiki/1994_European_Grand_Prix
271	1994	15	22	Japanese Grand Prix	1994-11-06	\N	http://en.wikipedia.org/wiki/1994_Japanese_Grand_Prix
272	1994	16	29	Australian Grand Prix	1994-11-13	\N	http://en.wikipedia.org/wiki/1994_Australian_Grand_Prix
273	1993	1	30	South African Grand Prix	1993-03-14	\N	http://en.wikipedia.org/wiki/1993_South_African_Grand_Prix
274	1993	2	18	Brazilian Grand Prix	1993-03-28	\N	http://en.wikipedia.org/wiki/1993_Brazilian_Grand_Prix
275	1993	3	31	European Grand Prix	1993-04-11	\N	http://en.wikipedia.org/wiki/1993_European_Grand_Prix
276	1993	4	21	San Marino Grand Prix	1993-04-25	\N	http://en.wikipedia.org/wiki/1993_San_Marino_Grand_Prix
277	1993	5	4	Spanish Grand Prix	1993-05-09	\N	http://en.wikipedia.org/wiki/1993_Spanish_Grand_Prix
278	1993	6	6	Monaco Grand Prix	1993-05-23	\N	http://en.wikipedia.org/wiki/1993_Monaco_Grand_Prix
279	1993	7	7	Canadian Grand Prix	1993-06-13	\N	http://en.wikipedia.org/wiki/1993_Canadian_Grand_Prix
280	1993	8	8	French Grand Prix	1993-07-04	\N	http://en.wikipedia.org/wiki/1993_French_Grand_Prix
281	1993	9	9	British Grand Prix	1993-07-11	\N	http://en.wikipedia.org/wiki/1993_British_Grand_Prix
282	1993	10	10	German Grand Prix	1993-07-25	\N	http://en.wikipedia.org/wiki/1993_German_Grand_Prix
283	1993	11	11	Hungarian Grand Prix	1993-08-15	\N	http://en.wikipedia.org/wiki/1993_Hungarian_Grand_Prix
284	1993	12	13	Belgian Grand Prix	1993-08-29	\N	http://en.wikipedia.org/wiki/1993_Belgian_Grand_Prix
285	1993	13	14	Italian Grand Prix	1993-09-12	\N	http://en.wikipedia.org/wiki/1993_Italian_Grand_Prix
286	1993	14	27	Portuguese Grand Prix	1993-09-26	\N	http://en.wikipedia.org/wiki/1993_Portuguese_Grand_Prix
287	1993	15	22	Japanese Grand Prix	1993-10-24	\N	http://en.wikipedia.org/wiki/1993_Japanese_Grand_Prix
288	1993	16	29	Australian Grand Prix	1993-11-07	\N	http://en.wikipedia.org/wiki/1993_Australian_Grand_Prix
289	1992	1	30	South African Grand Prix	1992-03-01	\N	http://en.wikipedia.org/wiki/1992_South_African_Grand_Prix
290	1992	2	32	Mexican Grand Prix	1992-03-22	\N	http://en.wikipedia.org/wiki/1992_Mexican_Grand_Prix
291	1992	3	18	Brazilian Grand Prix	1992-04-05	\N	http://en.wikipedia.org/wiki/1992_Brazilian_Grand_Prix
292	1992	4	4	Spanish Grand Prix	1992-05-03	\N	http://en.wikipedia.org/wiki/1992_Spanish_Grand_Prix
293	1992	5	21	San Marino Grand Prix	1992-05-17	\N	http://en.wikipedia.org/wiki/1992_San_Marino_Grand_Prix
294	1992	6	6	Monaco Grand Prix	1992-05-31	\N	http://en.wikipedia.org/wiki/1992_Monaco_Grand_Prix
295	1992	7	7	Canadian Grand Prix	1992-06-14	\N	http://en.wikipedia.org/wiki/1992_Canadian_Grand_Prix
296	1992	8	8	French Grand Prix	1992-07-05	\N	http://en.wikipedia.org/wiki/1992_French_Grand_Prix
297	1992	9	9	British Grand Prix	1992-07-12	\N	http://en.wikipedia.org/wiki/1992_British_Grand_Prix
298	1992	10	10	German Grand Prix	1992-07-26	\N	http://en.wikipedia.org/wiki/1992_German_Grand_Prix
299	1992	11	11	Hungarian Grand Prix	1992-08-16	\N	http://en.wikipedia.org/wiki/1992_Hungarian_Grand_Prix
300	1992	12	13	Belgian Grand Prix	1992-08-30	\N	http://en.wikipedia.org/wiki/1992_Belgian_Grand_Prix
301	1992	13	14	Italian Grand Prix	1992-09-13	\N	http://en.wikipedia.org/wiki/1992_Italian_Grand_Prix
302	1992	14	27	Portuguese Grand Prix	1992-09-27	\N	http://en.wikipedia.org/wiki/1992_Portuguese_Grand_Prix
303	1992	15	22	Japanese Grand Prix	1992-10-25	\N	http://en.wikipedia.org/wiki/1992_Japanese_Grand_Prix
304	1992	16	29	Australian Grand Prix	1992-11-08	\N	http://en.wikipedia.org/wiki/1992_Australian_Grand_Prix
305	1991	1	33	United States Grand Prix	1991-03-10	\N	http://en.wikipedia.org/wiki/1991_United_States_Grand_Prix
306	1991	2	18	Brazilian Grand Prix	1991-03-24	\N	http://en.wikipedia.org/wiki/1991_Brazilian_Grand_Prix
307	1991	3	21	San Marino Grand Prix	1991-04-28	\N	http://en.wikipedia.org/wiki/1991_San_Marino_Grand_Prix
308	1991	4	6	Monaco Grand Prix	1991-05-12	\N	http://en.wikipedia.org/wiki/1991_Monaco_Grand_Prix
309	1991	5	7	Canadian Grand Prix	1991-06-02	\N	http://en.wikipedia.org/wiki/1991_Canadian_Grand_Prix
310	1991	6	32	Mexican Grand Prix	1991-06-16	\N	http://en.wikipedia.org/wiki/1991_Mexican_Grand_Prix
311	1991	7	8	French Grand Prix	1991-07-07	\N	http://en.wikipedia.org/wiki/1991_French_Grand_Prix
312	1991	8	9	British Grand Prix	1991-07-14	\N	http://en.wikipedia.org/wiki/1991_British_Grand_Prix
313	1991	9	10	German Grand Prix	1991-07-28	\N	http://en.wikipedia.org/wiki/1991_German_Grand_Prix
314	1991	10	11	Hungarian Grand Prix	1991-08-11	\N	http://en.wikipedia.org/wiki/1991_Hungarian_Grand_Prix
315	1991	11	13	Belgian Grand Prix	1991-08-25	\N	http://en.wikipedia.org/wiki/1991_Belgian_Grand_Prix
316	1991	12	14	Italian Grand Prix	1991-09-08	\N	http://en.wikipedia.org/wiki/1991_Italian_Grand_Prix
317	1991	13	27	Portuguese Grand Prix	1991-09-22	\N	http://en.wikipedia.org/wiki/1991_Portuguese_Grand_Prix
318	1991	14	4	Spanish Grand Prix	1991-09-29	\N	http://en.wikipedia.org/wiki/1991_Spanish_Grand_Prix
319	1991	15	22	Japanese Grand Prix	1991-10-20	\N	http://en.wikipedia.org/wiki/1991_Japanese_Grand_Prix
320	1991	16	29	Australian Grand Prix	1991-11-03	\N	http://en.wikipedia.org/wiki/1991_Australian_Grand_Prix
321	1990	1	33	United States Grand Prix	1990-03-11	\N	http://en.wikipedia.org/wiki/1990_United_States_Grand_Prix
322	1990	2	18	Brazilian Grand Prix	1990-03-25	\N	http://en.wikipedia.org/wiki/1990_Brazilian_Grand_Prix
323	1990	3	21	San Marino Grand Prix	1990-05-13	\N	http://en.wikipedia.org/wiki/1990_San_Marino_Grand_Prix
324	1990	4	6	Monaco Grand Prix	1990-05-27	\N	http://en.wikipedia.org/wiki/1990_Monaco_Grand_Prix
325	1990	5	7	Canadian Grand Prix	1990-06-10	\N	http://en.wikipedia.org/wiki/1990_Canadian_Grand_Prix
326	1990	6	32	Mexican Grand Prix	1990-06-24	\N	http://en.wikipedia.org/wiki/1990_Mexican_Grand_Prix
327	1990	7	34	French Grand Prix	1990-07-08	\N	http://en.wikipedia.org/wiki/1990_French_Grand_Prix
328	1990	8	9	British Grand Prix	1990-07-15	\N	http://en.wikipedia.org/wiki/1990_British_Grand_Prix
329	1990	9	10	German Grand Prix	1990-07-29	\N	http://en.wikipedia.org/wiki/1990_German_Grand_Prix
330	1990	10	11	Hungarian Grand Prix	1990-08-12	\N	http://en.wikipedia.org/wiki/1990_Hungarian_Grand_Prix
331	1990	11	13	Belgian Grand Prix	1990-08-26	\N	http://en.wikipedia.org/wiki/1990_Belgian_Grand_Prix
332	1990	12	14	Italian Grand Prix	1990-09-09	\N	http://en.wikipedia.org/wiki/1990_Italian_Grand_Prix
333	1990	13	27	Portuguese Grand Prix	1990-09-23	\N	http://en.wikipedia.org/wiki/1990_Portuguese_Grand_Prix
334	1990	14	26	Spanish Grand Prix	1990-09-30	\N	http://en.wikipedia.org/wiki/1990_Spanish_Grand_Prix
335	1990	15	22	Japanese Grand Prix	1990-10-21	\N	http://en.wikipedia.org/wiki/1990_Japanese_Grand_Prix
336	1990	16	29	Australian Grand Prix	1990-11-04	\N	http://en.wikipedia.org/wiki/1990_Australian_Grand_Prix
337	2010	1	3	Bahrain Grand Prix	2010-03-14	12:00:00	http://en.wikipedia.org/wiki/2010_Bahrain_Grand_Prix
338	2010	2	1	Australian Grand Prix	2010-03-28	06:00:00	http://en.wikipedia.org/wiki/2010_Australian_Grand_Prix
339	2010	3	2	Malaysian Grand Prix	2010-04-04	08:00:00	http://en.wikipedia.org/wiki/2010_Malaysian_Grand_Prix
340	2010	4	17	Chinese Grand Prix	2010-04-18	06:00:00	http://en.wikipedia.org/wiki/2010_Chinese_Grand_Prix
341	2010	5	4	Spanish Grand Prix	2010-05-09	12:00:00	http://en.wikipedia.org/wiki/2010_Spanish_Grand_Prix
342	2010	6	6	Monaco Grand Prix	2010-05-16	12:00:00	http://en.wikipedia.org/wiki/2010_Monaco_Grand_Prix
343	2010	7	5	Turkish Grand Prix	2010-05-30	11:00:00	http://en.wikipedia.org/wiki/2010_Turkish_Grand_Prix
344	2010	8	7	Canadian Grand Prix	2010-06-13	16:00:00	http://en.wikipedia.org/wiki/2010_Canadian_Grand_Prix
345	2010	9	12	European Grand Prix	2010-06-27	12:00:00	http://en.wikipedia.org/wiki/2010_European_Grand_Prix
346	2010	10	9	British Grand Prix	2010-07-11	12:00:00	http://en.wikipedia.org/wiki/2010_British_Grand_Prix
347	2010	11	10	German Grand Prix	2010-07-25	12:00:00	http://en.wikipedia.org/wiki/2010_German_Grand_Prix
348	2010	12	11	Hungarian Grand Prix	2010-08-01	12:00:00	http://en.wikipedia.org/wiki/2010_Hungarian_Grand_Prix
349	2010	13	13	Belgian Grand Prix	2010-08-29	12:00:00	http://en.wikipedia.org/wiki/2010_Belgian_Grand_Prix
350	2010	14	14	Italian Grand Prix	2010-09-12	12:00:00	http://en.wikipedia.org/wiki/2010_Italian_Grand_Prix
351	2010	15	15	Singapore Grand Prix	2010-09-26	12:00:00	http://en.wikipedia.org/wiki/2010_Singapore_Grand_Prix
352	2010	16	22	Japanese Grand Prix	2010-10-10	06:00:00	http://en.wikipedia.org/wiki/2010_Japanese_Grand_Prix
353	2010	17	35	Korean Grand Prix	2010-10-24	05:00:00	http://en.wikipedia.org/wiki/2010_Korean_Grand_Prix
354	2010	18	18	Brazilian Grand Prix	2010-11-07	16:00:00	http://en.wikipedia.org/wiki/2010_Brazilian_Grand_Prix
355	2010	19	24	Abu Dhabi Grand Prix	2010-11-14	13:00:00	http://en.wikipedia.org/wiki/2010_Abu_Dhabi_Grand_Prix
356	1989	1	36	Brazilian Grand Prix	1989-03-26	\N	http://en.wikipedia.org/wiki/1989_Brazilian_Grand_Prix
357	1989	2	21	San Marino Grand Prix	1989-04-23	\N	http://en.wikipedia.org/wiki/1989_San_Marino_Grand_Prix
358	1989	3	6	Monaco Grand Prix	1989-05-07	\N	http://en.wikipedia.org/wiki/1989_Monaco_Grand_Prix
359	1989	4	32	Mexican Grand Prix	1989-05-28	\N	http://en.wikipedia.org/wiki/1989_Mexican_Grand_Prix
360	1989	5	33	United States Grand Prix	1989-06-04	\N	http://en.wikipedia.org/wiki/1989_United_States_Grand_Prix
361	1989	6	7	Canadian Grand Prix	1989-06-18	\N	http://en.wikipedia.org/wiki/1989_Canadian_Grand_Prix
362	1989	7	34	French Grand Prix	1989-07-09	\N	http://en.wikipedia.org/wiki/1989_French_Grand_Prix
363	1989	8	9	British Grand Prix	1989-07-16	\N	http://en.wikipedia.org/wiki/1989_British_Grand_Prix
364	1989	9	10	German Grand Prix	1989-07-30	\N	http://en.wikipedia.org/wiki/1989_German_Grand_Prix
365	1989	10	11	Hungarian Grand Prix	1989-08-13	\N	http://en.wikipedia.org/wiki/1989_Hungarian_Grand_Prix
366	1989	11	13	Belgian Grand Prix	1989-08-27	\N	http://en.wikipedia.org/wiki/1989_Belgian_Grand_Prix
367	1989	12	14	Italian Grand Prix	1989-09-10	\N	http://en.wikipedia.org/wiki/1989_Italian_Grand_Prix
368	1989	13	27	Portuguese Grand Prix	1989-09-24	\N	http://en.wikipedia.org/wiki/1989_Portuguese_Grand_Prix
369	1989	14	26	Spanish Grand Prix	1989-10-01	\N	http://en.wikipedia.org/wiki/1989_Spanish_Grand_Prix
370	1989	15	22	Japanese Grand Prix	1989-10-22	\N	http://en.wikipedia.org/wiki/1989_Japanese_Grand_Prix
371	1989	16	29	Australian Grand Prix	1989-11-05	\N	http://en.wikipedia.org/wiki/1989_Australian_Grand_Prix
372	1988	1	36	Brazilian Grand Prix	1988-04-03	\N	http://en.wikipedia.org/wiki/1988_Brazilian_Grand_Prix
373	1988	2	21	San Marino Grand Prix	1988-05-01	\N	http://en.wikipedia.org/wiki/1988_San_Marino_Grand_Prix
374	1988	3	6	Monaco Grand Prix	1988-05-15	\N	http://en.wikipedia.org/wiki/1988_Monaco_Grand_Prix
375	1988	4	32	Mexican Grand Prix	1988-05-29	\N	http://en.wikipedia.org/wiki/1988_Mexican_Grand_Prix
376	1988	5	7	Canadian Grand Prix	1988-06-12	\N	http://en.wikipedia.org/wiki/1988_Canadian_Grand_Prix
377	1988	6	37	Detroit Grand Prix	1988-06-19	\N	http://en.wikipedia.org/wiki/1988_Detroit_Grand_Prix
378	1988	7	34	French Grand Prix	1988-07-03	\N	http://en.wikipedia.org/wiki/1988_French_Grand_Prix
379	1988	8	9	British Grand Prix	1988-07-10	\N	http://en.wikipedia.org/wiki/1988_British_Grand_Prix
380	1988	9	10	German Grand Prix	1988-07-24	\N	http://en.wikipedia.org/wiki/1988_German_Grand_Prix
381	1988	10	11	Hungarian Grand Prix	1988-08-07	\N	http://en.wikipedia.org/wiki/1988_Hungarian_Grand_Prix
382	1988	11	13	Belgian Grand Prix	1988-08-28	\N	http://en.wikipedia.org/wiki/1988_Belgian_Grand_Prix
383	1988	12	14	Italian Grand Prix	1988-09-11	\N	http://en.wikipedia.org/wiki/1988_Italian_Grand_Prix
384	1988	13	27	Portuguese Grand Prix	1988-09-25	\N	http://en.wikipedia.org/wiki/1988_Portuguese_Grand_Prix
385	1988	14	26	Spanish Grand Prix	1988-10-02	\N	http://en.wikipedia.org/wiki/1988_Spanish_Grand_Prix
386	1988	15	22	Japanese Grand Prix	1988-10-30	\N	http://en.wikipedia.org/wiki/1988_Japanese_Grand_Prix
387	1988	16	29	Australian Grand Prix	1988-11-13	\N	http://en.wikipedia.org/wiki/1988_Australian_Grand_Prix
388	1987	1	36	Brazilian Grand Prix	1987-04-12	\N	http://en.wikipedia.org/wiki/1987_Brazilian_Grand_Prix
389	1987	2	21	San Marino Grand Prix	1987-05-03	\N	http://en.wikipedia.org/wiki/1987_San_Marino_Grand_Prix
390	1987	3	13	Belgian Grand Prix	1987-05-17	\N	http://en.wikipedia.org/wiki/1987_Belgian_Grand_Prix
391	1987	4	6	Monaco Grand Prix	1987-05-31	\N	http://en.wikipedia.org/wiki/1987_Monaco_Grand_Prix
392	1987	5	37	Detroit Grand Prix	1987-06-21	\N	http://en.wikipedia.org/wiki/1987_Detroit_Grand_Prix
393	1987	6	34	French Grand Prix	1987-07-05	\N	http://en.wikipedia.org/wiki/1987_French_Grand_Prix
394	1987	7	9	British Grand Prix	1987-07-12	\N	http://en.wikipedia.org/wiki/1987_British_Grand_Prix
395	1987	8	10	German Grand Prix	1987-07-26	\N	http://en.wikipedia.org/wiki/1987_German_Grand_Prix
396	1987	9	11	Hungarian Grand Prix	1987-08-09	\N	http://en.wikipedia.org/wiki/1987_Hungarian_Grand_Prix
397	1987	10	23	Austrian Grand Prix	1987-08-16	\N	http://en.wikipedia.org/wiki/1987_Austrian_Grand_Prix
398	1987	11	14	Italian Grand Prix	1987-09-06	\N	http://en.wikipedia.org/wiki/1987_Italian_Grand_Prix
399	1987	12	27	Portuguese Grand Prix	1987-09-20	\N	http://en.wikipedia.org/wiki/1987_Portuguese_Grand_Prix
400	1987	13	26	Spanish Grand Prix	1987-09-27	\N	http://en.wikipedia.org/wiki/1987_Spanish_Grand_Prix
401	1987	14	32	Mexican Grand Prix	1987-10-18	\N	http://en.wikipedia.org/wiki/1987_Mexican_Grand_Prix
402	1987	15	22	Japanese Grand Prix	1987-11-01	\N	http://en.wikipedia.org/wiki/1987_Japanese_Grand_Prix
403	1987	16	29	Australian Grand Prix	1987-11-15	\N	http://en.wikipedia.org/wiki/1987_Australian_Grand_Prix
404	1986	1	36	Brazilian Grand Prix	1986-03-23	\N	http://en.wikipedia.org/wiki/1986_Brazilian_Grand_Prix
405	1986	2	26	Spanish Grand Prix	1986-04-13	\N	http://en.wikipedia.org/wiki/1986_Spanish_Grand_Prix
406	1986	3	21	San Marino Grand Prix	1986-04-27	\N	http://en.wikipedia.org/wiki/1986_San_Marino_Grand_Prix
407	1986	4	6	Monaco Grand Prix	1986-05-11	\N	http://en.wikipedia.org/wiki/1986_Monaco_Grand_Prix
408	1986	5	13	Belgian Grand Prix	1986-05-25	\N	http://en.wikipedia.org/wiki/1986_Belgian_Grand_Prix
409	1986	6	7	Canadian Grand Prix	1986-06-15	\N	http://en.wikipedia.org/wiki/1986_Canadian_Grand_Prix
410	1986	7	37	Detroit Grand Prix	1986-06-22	\N	http://en.wikipedia.org/wiki/1986_Detroit_Grand_Prix
411	1986	8	34	French Grand Prix	1986-07-06	\N	http://en.wikipedia.org/wiki/1986_French_Grand_Prix
412	1986	9	38	British Grand Prix	1986-07-13	\N	http://en.wikipedia.org/wiki/1986_British_Grand_Prix
413	1986	10	10	German Grand Prix	1986-07-27	\N	http://en.wikipedia.org/wiki/1986_German_Grand_Prix
414	1986	11	11	Hungarian Grand Prix	1986-08-10	\N	http://en.wikipedia.org/wiki/1986_Hungarian_Grand_Prix
415	1986	12	23	Austrian Grand Prix	1986-08-17	\N	http://en.wikipedia.org/wiki/1986_Austrian_Grand_Prix
416	1986	13	14	Italian Grand Prix	1986-09-07	\N	http://en.wikipedia.org/wiki/1986_Italian_Grand_Prix
417	1986	14	27	Portuguese Grand Prix	1986-09-21	\N	http://en.wikipedia.org/wiki/1986_Portuguese_Grand_Prix
418	1986	15	32	Mexican Grand Prix	1986-10-12	\N	http://en.wikipedia.org/wiki/1986_Mexican_Grand_Prix
419	1986	16	29	Australian Grand Prix	1986-10-26	\N	http://en.wikipedia.org/wiki/1986_Australian_Grand_Prix
420	1985	1	36	Brazilian Grand Prix	1985-04-07	\N	http://en.wikipedia.org/wiki/1985_Brazilian_Grand_Prix
421	1985	2	27	Portuguese Grand Prix	1985-04-21	\N	http://en.wikipedia.org/wiki/1985_Portuguese_Grand_Prix
422	1985	3	21	San Marino Grand Prix	1985-05-05	\N	http://en.wikipedia.org/wiki/1985_San_Marino_Grand_Prix
423	1985	4	6	Monaco Grand Prix	1985-05-19	\N	http://en.wikipedia.org/wiki/1985_Monaco_Grand_Prix
424	1985	5	7	Canadian Grand Prix	1985-06-16	\N	http://en.wikipedia.org/wiki/1985_Canadian_Grand_Prix
425	1985	6	37	Detroit Grand Prix	1985-06-23	\N	http://en.wikipedia.org/wiki/1985_Detroit_Grand_Prix
426	1985	7	34	French Grand Prix	1985-07-07	\N	http://en.wikipedia.org/wiki/1985_French_Grand_Prix
427	1985	8	9	British Grand Prix	1985-07-21	\N	http://en.wikipedia.org/wiki/1985_British_Grand_Prix
428	1985	9	20	German Grand Prix	1985-08-04	\N	http://en.wikipedia.org/wiki/1985_German_Grand_Prix
429	1985	10	23	Austrian Grand Prix	1985-08-18	\N	http://en.wikipedia.org/wiki/1985_Austrian_Grand_Prix
430	1985	11	39	Dutch Grand Prix	1985-08-25	\N	http://en.wikipedia.org/wiki/1985_Dutch_Grand_Prix
431	1985	12	14	Italian Grand Prix	1985-09-08	\N	http://en.wikipedia.org/wiki/1985_Italian_Grand_Prix
432	1985	13	13	Belgian Grand Prix	1985-09-15	\N	http://en.wikipedia.org/wiki/1985_Belgian_Grand_Prix
433	1985	14	38	European Grand Prix	1985-10-06	\N	http://en.wikipedia.org/wiki/1985_European_Grand_Prix
434	1985	15	30	South African Grand Prix	1985-10-19	\N	http://en.wikipedia.org/wiki/1985_South_African_Grand_Prix
435	1985	16	29	Australian Grand Prix	1985-11-03	\N	http://en.wikipedia.org/wiki/1985_Australian_Grand_Prix
436	1984	1	36	Brazilian Grand Prix	1984-03-25	\N	http://en.wikipedia.org/wiki/1984_Brazilian_Grand_Prix
437	1984	2	30	South African Grand Prix	1984-04-07	\N	http://en.wikipedia.org/wiki/1984_South_African_Grand_Prix
438	1984	3	40	Belgian Grand Prix	1984-04-29	\N	http://en.wikipedia.org/wiki/1984_Belgian_Grand_Prix
439	1984	4	21	San Marino Grand Prix	1984-05-06	\N	http://en.wikipedia.org/wiki/1984_San_Marino_Grand_Prix
440	1984	5	41	French Grand Prix	1984-05-20	\N	http://en.wikipedia.org/wiki/1984_French_Grand_Prix
441	1984	6	6	Monaco Grand Prix	1984-06-03	\N	http://en.wikipedia.org/wiki/1984_Monaco_Grand_Prix
442	1984	7	7	Canadian Grand Prix	1984-06-17	\N	http://en.wikipedia.org/wiki/1984_Canadian_Grand_Prix
443	1984	8	37	Detroit Grand Prix	1984-06-24	\N	http://en.wikipedia.org/wiki/1984_Detroit_Grand_Prix
444	1984	9	42	Dallas Grand Prix	1984-07-08	\N	http://en.wikipedia.org/wiki/1984_Dallas_Grand_Prix
445	1984	10	38	British Grand Prix	1984-07-22	\N	http://en.wikipedia.org/wiki/1984_British_Grand_Prix
446	1984	11	10	German Grand Prix	1984-08-05	\N	http://en.wikipedia.org/wiki/1984_German_Grand_Prix
447	1984	12	23	Austrian Grand Prix	1984-08-19	\N	http://en.wikipedia.org/wiki/1984_Austrian_Grand_Prix
448	1984	13	39	Dutch Grand Prix	1984-08-26	\N	http://en.wikipedia.org/wiki/1984_Dutch_Grand_Prix
449	1984	14	14	Italian Grand Prix	1984-09-09	\N	http://en.wikipedia.org/wiki/1984_Italian_Grand_Prix
450	1984	15	20	European Grand Prix	1984-10-07	\N	http://en.wikipedia.org/wiki/1984_European_Grand_Prix
451	1984	16	27	Portuguese Grand Prix	1984-10-21	\N	http://en.wikipedia.org/wiki/1984_Portuguese_Grand_Prix
452	1983	1	36	Brazilian Grand Prix	1983-03-13	\N	http://en.wikipedia.org/wiki/1983_Brazilian_Grand_Prix
453	1983	2	43	United States Grand Prix West	1983-03-27	\N	http://en.wikipedia.org/wiki/1983_United_States_Grand_Prix_West
454	1983	3	34	French Grand Prix	1983-04-17	\N	http://en.wikipedia.org/wiki/1983_French_Grand_Prix
455	1983	4	21	San Marino Grand Prix	1983-05-01	\N	http://en.wikipedia.org/wiki/1983_San_Marino_Grand_Prix
456	1983	5	6	Monaco Grand Prix	1983-05-15	\N	http://en.wikipedia.org/wiki/1983_Monaco_Grand_Prix
457	1983	6	13	Belgian Grand Prix	1983-05-22	\N	http://en.wikipedia.org/wiki/1983_Belgian_Grand_Prix
458	1983	7	37	Detroit Grand Prix	1983-06-05	\N	http://en.wikipedia.org/wiki/1983_Detroit_Grand_Prix
459	1983	8	7	Canadian Grand Prix	1983-06-12	\N	http://en.wikipedia.org/wiki/1983_Canadian_Grand_Prix
460	1983	9	9	British Grand Prix	1983-07-16	\N	http://en.wikipedia.org/wiki/1983_British_Grand_Prix
461	1983	10	10	German Grand Prix	1983-08-07	\N	http://en.wikipedia.org/wiki/1983_German_Grand_Prix
462	1983	11	23	Austrian Grand Prix	1983-08-14	\N	http://en.wikipedia.org/wiki/1983_Austrian_Grand_Prix
463	1983	12	39	Dutch Grand Prix	1983-08-28	\N	http://en.wikipedia.org/wiki/1983_Dutch_Grand_Prix
464	1983	13	14	Italian Grand Prix	1983-09-11	\N	http://en.wikipedia.org/wiki/1983_Italian_Grand_Prix
465	1983	14	38	European Grand Prix	1983-09-25	\N	http://en.wikipedia.org/wiki/1983_European_Grand_Prix
466	1983	15	30	South African Grand Prix	1983-10-15	\N	http://en.wikipedia.org/wiki/1983_South_African_Grand_Prix
467	1982	1	30	South African Grand Prix	1982-01-23	\N	http://en.wikipedia.org/wiki/1982_South_African_Grand_Prix
468	1982	2	36	Brazilian Grand Prix	1982-03-21	\N	http://en.wikipedia.org/wiki/1982_Brazilian_Grand_Prix
469	1982	3	43	United States Grand Prix West	1982-04-04	\N	http://en.wikipedia.org/wiki/1982_United_States_Grand_Prix_West
470	1982	4	21	San Marino Grand Prix	1982-04-25	\N	http://en.wikipedia.org/wiki/1982_San_Marino_Grand_Prix
471	1982	5	40	Belgian Grand Prix	1982-05-09	\N	http://en.wikipedia.org/wiki/1982_Belgian_Grand_Prix
472	1982	6	6	Monaco Grand Prix	1982-05-23	\N	http://en.wikipedia.org/wiki/1982_Monaco_Grand_Prix
473	1982	7	37	Detroit Grand Prix	1982-06-06	\N	http://en.wikipedia.org/wiki/1982_Detroit_Grand_Prix
474	1982	8	7	Canadian Grand Prix	1982-06-13	\N	http://en.wikipedia.org/wiki/1982_Canadian_Grand_Prix
475	1982	9	39	Dutch Grand Prix	1982-07-03	\N	http://en.wikipedia.org/wiki/1982_Dutch_Grand_Prix
476	1982	10	38	British Grand Prix	1982-07-18	\N	http://en.wikipedia.org/wiki/1982_British_Grand_Prix
477	1982	11	34	French Grand Prix	1982-07-25	\N	http://en.wikipedia.org/wiki/1982_French_Grand_Prix
478	1982	12	10	German Grand Prix	1982-08-08	\N	http://en.wikipedia.org/wiki/1982_German_Grand_Prix
479	1982	13	23	Austrian Grand Prix	1982-08-15	\N	http://en.wikipedia.org/wiki/1982_Austrian_Grand_Prix
480	1982	14	41	Swiss Grand Prix	1982-08-29	\N	http://en.wikipedia.org/wiki/1982_Swiss_Grand_Prix
481	1982	15	14	Italian Grand Prix	1982-09-12	\N	http://en.wikipedia.org/wiki/1982_Italian_Grand_Prix
482	1982	16	44	Caesars Palace Grand Prix	1982-09-25	\N	http://en.wikipedia.org/wiki/1982_Caesars_Palace_Grand_Prix
483	1981	1	43	United States Grand Prix West	1981-03-15	\N	http://en.wikipedia.org/wiki/1981_United_States_Grand_Prix_West
484	1981	2	36	Brazilian Grand Prix	1981-03-29	\N	http://en.wikipedia.org/wiki/1981_Brazilian_Grand_Prix
485	1981	3	25	Argentine Grand Prix	1981-04-12	\N	http://en.wikipedia.org/wiki/1981_Argentine_Grand_Prix
486	1981	4	21	San Marino Grand Prix	1981-05-03	\N	http://en.wikipedia.org/wiki/1981_San_Marino_Grand_Prix
487	1981	5	40	Belgian Grand Prix	1981-05-17	\N	http://en.wikipedia.org/wiki/1981_Belgian_Grand_Prix
488	1981	6	6	Monaco Grand Prix	1981-05-31	\N	http://en.wikipedia.org/wiki/1981_Monaco_Grand_Prix
489	1981	7	45	Spanish Grand Prix	1981-06-21	\N	http://en.wikipedia.org/wiki/1981_Spanish_Grand_Prix
490	1981	8	41	French Grand Prix	1981-07-05	\N	http://en.wikipedia.org/wiki/1981_French_Grand_Prix
491	1981	9	9	British Grand Prix	1981-07-18	\N	http://en.wikipedia.org/wiki/1981_British_Grand_Prix
492	1981	10	10	German Grand Prix	1981-08-02	\N	http://en.wikipedia.org/wiki/1981_German_Grand_Prix
493	1981	11	23	Austrian Grand Prix	1981-08-16	\N	http://en.wikipedia.org/wiki/1981_Austrian_Grand_Prix
494	1981	12	39	Dutch Grand Prix	1981-08-30	\N	http://en.wikipedia.org/wiki/1981_Dutch_Grand_Prix
495	1981	13	14	Italian Grand Prix	1981-09-13	\N	http://en.wikipedia.org/wiki/1981_Italian_Grand_Prix
496	1981	14	7	Canadian Grand Prix	1981-09-27	\N	http://en.wikipedia.org/wiki/1981_Canadian_Grand_Prix
497	1981	15	44	Caesars Palace Grand Prix	1981-10-17	\N	http://en.wikipedia.org/wiki/1981_Caesars_Palace_Grand_Prix
498	1980	1	25	Argentine Grand Prix	1980-01-13	\N	http://en.wikipedia.org/wiki/1980_Argentine_Grand_Prix
499	1980	2	18	Brazilian Grand Prix	1980-01-27	\N	http://en.wikipedia.org/wiki/1980_Brazilian_Grand_Prix
500	1980	3	30	South African Grand Prix	1980-03-01	\N	http://en.wikipedia.org/wiki/1980_South_African_Grand_Prix
501	1980	4	43	United States Grand Prix West	1980-03-30	\N	http://en.wikipedia.org/wiki/1980_United_States_Grand_Prix_West
502	1980	5	40	Belgian Grand Prix	1980-05-04	\N	http://en.wikipedia.org/wiki/1980_Belgian_Grand_Prix
503	1980	6	6	Monaco Grand Prix	1980-05-18	\N	http://en.wikipedia.org/wiki/1980_Monaco_Grand_Prix
504	1980	7	34	French Grand Prix	1980-06-29	\N	http://en.wikipedia.org/wiki/1980_French_Grand_Prix
505	1980	8	38	British Grand Prix	1980-07-13	\N	http://en.wikipedia.org/wiki/1980_British_Grand_Prix
506	1980	9	10	German Grand Prix	1980-08-10	\N	http://en.wikipedia.org/wiki/1980_German_Grand_Prix
507	1980	10	23	Austrian Grand Prix	1980-08-17	\N	http://en.wikipedia.org/wiki/1980_Austrian_Grand_Prix
508	1980	11	39	Dutch Grand Prix	1980-08-31	\N	http://en.wikipedia.org/wiki/1980_Dutch_Grand_Prix
509	1980	12	21	Italian Grand Prix	1980-09-14	\N	http://en.wikipedia.org/wiki/1980_Italian_Grand_Prix
510	1980	13	7	Canadian Grand Prix	1980-09-28	\N	http://en.wikipedia.org/wiki/1980_Canadian_Grand_Prix
511	1980	14	46	United States Grand Prix	1980-10-05	\N	http://en.wikipedia.org/wiki/1980_United_States_Grand_Prix
512	1979	1	25	Argentine Grand Prix	1979-01-21	\N	http://en.wikipedia.org/wiki/1979_Argentine_Grand_Prix
513	1979	2	18	Brazilian Grand Prix	1979-02-04	\N	http://en.wikipedia.org/wiki/1979_Brazilian_Grand_Prix
514	1979	3	30	South African Grand Prix	1979-03-03	\N	http://en.wikipedia.org/wiki/1979_South_African_Grand_Prix
515	1979	4	43	United States Grand Prix West	1979-04-08	\N	http://en.wikipedia.org/wiki/1979_United_States_Grand_Prix_West
516	1979	5	45	Spanish Grand Prix	1979-04-29	\N	http://en.wikipedia.org/wiki/1979_Spanish_Grand_Prix
517	1979	6	40	Belgian Grand Prix	1979-05-13	\N	http://en.wikipedia.org/wiki/1979_Belgian_Grand_Prix
518	1979	7	6	Monaco Grand Prix	1979-05-27	\N	http://en.wikipedia.org/wiki/1979_Monaco_Grand_Prix
519	1979	8	41	French Grand Prix	1979-07-01	\N	http://en.wikipedia.org/wiki/1979_French_Grand_Prix
520	1979	9	9	British Grand Prix	1979-07-14	\N	http://en.wikipedia.org/wiki/1979_British_Grand_Prix
521	1979	10	10	German Grand Prix	1979-07-29	\N	http://en.wikipedia.org/wiki/1979_German_Grand_Prix
522	1979	11	23	Austrian Grand Prix	1979-08-12	\N	http://en.wikipedia.org/wiki/1979_Austrian_Grand_Prix
523	1979	12	39	Dutch Grand Prix	1979-08-26	\N	http://en.wikipedia.org/wiki/1979_Dutch_Grand_Prix
524	1979	13	14	Italian Grand Prix	1979-09-09	\N	http://en.wikipedia.org/wiki/1979_Italian_Grand_Prix
525	1979	14	7	Canadian Grand Prix	1979-09-30	\N	http://en.wikipedia.org/wiki/1979_Canadian_Grand_Prix
526	1979	15	46	United States Grand Prix	1979-10-07	\N	http://en.wikipedia.org/wiki/1979_United_States_Grand_Prix
527	1978	1	25	Argentine Grand Prix	1978-01-15	\N	http://en.wikipedia.org/wiki/1978_Argentine_Grand_Prix
528	1978	2	36	Brazilian Grand Prix	1978-01-29	\N	http://en.wikipedia.org/wiki/1978_Brazilian_Grand_Prix
529	1978	3	30	South African Grand Prix	1978-03-04	\N	http://en.wikipedia.org/wiki/1978_South_African_Grand_Prix
530	1978	4	43	United States Grand Prix West	1978-04-02	\N	http://en.wikipedia.org/wiki/1978_United_States_Grand_Prix_West
531	1978	5	6	Monaco Grand Prix	1978-05-07	\N	http://en.wikipedia.org/wiki/1978_Monaco_Grand_Prix
532	1978	6	40	Belgian Grand Prix	1978-05-21	\N	http://en.wikipedia.org/wiki/1978_Belgian_Grand_Prix
533	1978	7	45	Spanish Grand Prix	1978-06-04	\N	http://en.wikipedia.org/wiki/1978_Spanish_Grand_Prix
534	1978	8	47	Swedish Grand Prix	1978-06-17	\N	http://en.wikipedia.org/wiki/1978_Swedish_Grand_Prix
535	1978	9	34	French Grand Prix	1978-07-02	\N	http://en.wikipedia.org/wiki/1978_French_Grand_Prix
536	1978	10	38	British Grand Prix	1978-07-16	\N	http://en.wikipedia.org/wiki/1978_British_Grand_Prix
537	1978	11	10	German Grand Prix	1978-07-30	\N	http://en.wikipedia.org/wiki/1978_German_Grand_Prix
538	1978	12	23	Austrian Grand Prix	1978-08-13	\N	http://en.wikipedia.org/wiki/1978_Austrian_Grand_Prix
539	1978	13	39	Dutch Grand Prix	1978-08-27	\N	http://en.wikipedia.org/wiki/1978_Dutch_Grand_Prix
540	1978	14	14	Italian Grand Prix	1978-09-10	\N	http://en.wikipedia.org/wiki/1978_Italian_Grand_Prix
541	1978	15	46	United States Grand Prix	1978-10-01	\N	http://en.wikipedia.org/wiki/1978_United_States_Grand_Prix
542	1978	16	7	Canadian Grand Prix	1978-10-08	\N	http://en.wikipedia.org/wiki/1978_Canadian_Grand_Prix
543	1977	1	25	Argentine Grand Prix	1977-01-09	\N	http://en.wikipedia.org/wiki/1977_Argentine_Grand_Prix
544	1977	2	18	Brazilian Grand Prix	1977-01-23	\N	http://en.wikipedia.org/wiki/1977_Brazilian_Grand_Prix
545	1977	3	30	South African Grand Prix	1977-03-05	\N	http://en.wikipedia.org/wiki/1977_South_African_Grand_Prix
546	1977	4	43	United States Grand Prix West	1977-04-03	\N	http://en.wikipedia.org/wiki/1977_United_States_Grand_Prix_West
547	1977	5	45	Spanish Grand Prix	1977-05-08	\N	http://en.wikipedia.org/wiki/1977_Spanish_Grand_Prix
548	1977	6	6	Monaco Grand Prix	1977-05-22	\N	http://en.wikipedia.org/wiki/1977_Monaco_Grand_Prix
549	1977	7	40	Belgian Grand Prix	1977-06-05	\N	http://en.wikipedia.org/wiki/1977_Belgian_Grand_Prix
550	1977	8	47	Swedish Grand Prix	1977-06-19	\N	http://en.wikipedia.org/wiki/1977_Swedish_Grand_Prix
551	1977	9	41	French Grand Prix	1977-07-03	\N	http://en.wikipedia.org/wiki/1977_French_Grand_Prix
552	1977	10	9	British Grand Prix	1977-07-16	\N	http://en.wikipedia.org/wiki/1977_British_Grand_Prix
553	1977	11	10	German Grand Prix	1977-07-31	\N	http://en.wikipedia.org/wiki/1977_German_Grand_Prix
554	1977	12	23	Austrian Grand Prix	1977-08-14	\N	http://en.wikipedia.org/wiki/1977_Austrian_Grand_Prix
555	1977	13	39	Dutch Grand Prix	1977-08-28	\N	http://en.wikipedia.org/wiki/1977_Dutch_Grand_Prix
556	1977	14	14	Italian Grand Prix	1977-09-11	\N	http://en.wikipedia.org/wiki/1977_Italian_Grand_Prix
557	1977	15	46	United States Grand Prix	1977-10-02	\N	http://en.wikipedia.org/wiki/1977_United_States_Grand_Prix
558	1977	16	48	Canadian Grand Prix	1977-10-09	\N	http://en.wikipedia.org/wiki/1977_Canadian_Grand_Prix
559	1977	17	16	Japanese Grand Prix	1977-10-23	\N	http://en.wikipedia.org/wiki/1977_Japanese_Grand_Prix
560	1976	1	18	Brazilian Grand Prix	1976-01-25	\N	http://en.wikipedia.org/wiki/1976_Brazilian_Grand_Prix
561	1976	2	30	South African Grand Prix	1976-03-06	\N	http://en.wikipedia.org/wiki/1976_South_African_Grand_Prix
562	1976	3	43	United States Grand Prix West	1976-03-28	\N	http://en.wikipedia.org/wiki/1976_United_States_Grand_Prix_West
563	1976	4	45	Spanish Grand Prix	1976-05-02	\N	http://en.wikipedia.org/wiki/1976_Spanish_Grand_Prix
564	1976	5	40	Belgian Grand Prix	1976-05-16	\N	http://en.wikipedia.org/wiki/1976_Belgian_Grand_Prix
565	1976	6	6	Monaco Grand Prix	1976-05-30	\N	http://en.wikipedia.org/wiki/1976_Monaco_Grand_Prix
566	1976	7	47	Swedish Grand Prix	1976-06-13	\N	http://en.wikipedia.org/wiki/1976_Swedish_Grand_Prix
567	1976	8	34	French Grand Prix	1976-07-04	\N	http://en.wikipedia.org/wiki/1976_French_Grand_Prix
568	1976	9	38	British Grand Prix	1976-07-18	\N	http://en.wikipedia.org/wiki/1976_British_Grand_Prix
569	1976	10	20	German Grand Prix	1976-08-01	\N	http://en.wikipedia.org/wiki/1976_German_Grand_Prix
570	1976	11	23	Austrian Grand Prix	1976-08-15	\N	http://en.wikipedia.org/wiki/1976_Austrian_Grand_Prix
571	1976	12	39	Dutch Grand Prix	1976-08-29	\N	http://en.wikipedia.org/wiki/1976_Dutch_Grand_Prix
572	1976	13	14	Italian Grand Prix	1976-09-12	\N	http://en.wikipedia.org/wiki/1976_Italian_Grand_Prix
573	1976	14	48	Canadian Grand Prix	1976-10-03	\N	http://en.wikipedia.org/wiki/1976_Canadian_Grand_Prix
574	1976	15	46	United States Grand Prix	1976-10-10	\N	http://en.wikipedia.org/wiki/1976_United_States_Grand_Prix
575	1976	16	16	Japanese Grand Prix	1976-10-24	\N	http://en.wikipedia.org/wiki/1976_Japanese_Grand_Prix
576	1975	1	25	Argentine Grand Prix	1975-01-12	\N	http://en.wikipedia.org/wiki/1975_Argentine_Grand_Prix
577	1975	2	18	Brazilian Grand Prix	1975-01-26	\N	http://en.wikipedia.org/wiki/1975_Brazilian_Grand_Prix
578	1975	3	30	South African Grand Prix	1975-03-01	\N	http://en.wikipedia.org/wiki/1975_South_African_Grand_Prix
579	1975	4	49	Spanish Grand Prix	1975-04-27	\N	http://en.wikipedia.org/wiki/1975_Spanish_Grand_Prix
580	1975	5	6	Monaco Grand Prix	1975-05-11	\N	http://en.wikipedia.org/wiki/1975_Monaco_Grand_Prix
581	1975	6	40	Belgian Grand Prix	1975-05-25	\N	http://en.wikipedia.org/wiki/1975_Belgian_Grand_Prix
582	1975	7	47	Swedish Grand Prix	1975-06-08	\N	http://en.wikipedia.org/wiki/1975_Swedish_Grand_Prix
583	1975	8	39	Dutch Grand Prix	1975-06-22	\N	http://en.wikipedia.org/wiki/1975_Dutch_Grand_Prix
584	1975	9	34	French Grand Prix	1975-07-06	\N	http://en.wikipedia.org/wiki/1975_French_Grand_Prix
585	1975	10	9	British Grand Prix	1975-07-19	\N	http://en.wikipedia.org/wiki/1975_British_Grand_Prix
586	1975	11	20	German Grand Prix	1975-08-03	\N	http://en.wikipedia.org/wiki/1975_German_Grand_Prix
587	1975	12	23	Austrian Grand Prix	1975-08-17	\N	http://en.wikipedia.org/wiki/1975_Austrian_Grand_Prix
588	1975	13	14	Italian Grand Prix	1975-09-07	\N	http://en.wikipedia.org/wiki/1975_Italian_Grand_Prix
589	1975	14	46	United States Grand Prix	1975-10-05	\N	http://en.wikipedia.org/wiki/1975_United_States_Grand_Prix
590	1974	1	25	Argentine Grand Prix	1974-01-13	\N	http://en.wikipedia.org/wiki/1974_Argentine_Grand_Prix
591	1974	2	18	Brazilian Grand Prix	1974-01-27	\N	http://en.wikipedia.org/wiki/1974_Brazilian_Grand_Prix
592	1974	3	30	South African Grand Prix	1974-03-30	\N	http://en.wikipedia.org/wiki/1974_South_African_Grand_Prix
593	1974	4	45	Spanish Grand Prix	1974-04-28	\N	http://en.wikipedia.org/wiki/1974_Spanish_Grand_Prix
594	1974	5	50	Belgian Grand Prix	1974-05-12	\N	http://en.wikipedia.org/wiki/1974_Belgian_Grand_Prix
595	1974	6	6	Monaco Grand Prix	1974-05-26	\N	http://en.wikipedia.org/wiki/1974_Monaco_Grand_Prix
596	1974	7	47	Swedish Grand Prix	1974-06-09	\N	http://en.wikipedia.org/wiki/1974_Swedish_Grand_Prix
597	1974	8	39	Dutch Grand Prix	1974-06-23	\N	http://en.wikipedia.org/wiki/1974_Dutch_Grand_Prix
598	1974	9	41	French Grand Prix	1974-07-07	\N	http://en.wikipedia.org/wiki/1974_French_Grand_Prix
599	1974	10	38	British Grand Prix	1974-07-20	\N	http://en.wikipedia.org/wiki/1974_British_Grand_Prix
600	1974	11	20	German Grand Prix	1974-08-04	\N	http://en.wikipedia.org/wiki/1974_German_Grand_Prix
601	1974	12	23	Austrian Grand Prix	1974-08-18	\N	http://en.wikipedia.org/wiki/1974_Austrian_Grand_Prix
602	1974	13	14	Italian Grand Prix	1974-09-08	\N	http://en.wikipedia.org/wiki/1974_Italian_Grand_Prix
603	1974	14	48	Canadian Grand Prix	1974-09-22	\N	http://en.wikipedia.org/wiki/1974_Canadian_Grand_Prix
604	1974	15	46	United States Grand Prix	1974-10-06	\N	http://en.wikipedia.org/wiki/1974_United_States_Grand_Prix
605	1973	1	25	Argentine Grand Prix	1973-01-28	\N	http://en.wikipedia.org/wiki/1973_Argentine_Grand_Prix
606	1973	2	18	Brazilian Grand Prix	1973-02-11	\N	http://en.wikipedia.org/wiki/1973_Brazilian_Grand_Prix
607	1973	3	30	South African Grand Prix	1973-03-03	\N	http://en.wikipedia.org/wiki/1973_South_African_Grand_Prix
608	1973	4	49	Spanish Grand Prix	1973-04-29	\N	http://en.wikipedia.org/wiki/1973_Spanish_Grand_Prix
609	1973	5	40	Belgian Grand Prix	1973-05-20	\N	http://en.wikipedia.org/wiki/1973_Belgian_Grand_Prix
610	1973	6	6	Monaco Grand Prix	1973-06-03	\N	http://en.wikipedia.org/wiki/1973_Monaco_Grand_Prix
611	1973	7	47	Swedish Grand Prix	1973-06-17	\N	http://en.wikipedia.org/wiki/1973_Swedish_Grand_Prix
612	1973	8	34	French Grand Prix	1973-07-01	\N	http://en.wikipedia.org/wiki/1973_French_Grand_Prix
613	1973	9	9	British Grand Prix	1973-07-14	\N	http://en.wikipedia.org/wiki/1973_British_Grand_Prix
614	1973	10	39	Dutch Grand Prix	1973-07-29	\N	http://en.wikipedia.org/wiki/1973_Dutch_Grand_Prix
615	1973	11	20	German Grand Prix	1973-08-05	\N	http://en.wikipedia.org/wiki/1973_German_Grand_Prix
616	1973	12	23	Austrian Grand Prix	1973-08-19	\N	http://en.wikipedia.org/wiki/1973_Austrian_Grand_Prix
617	1973	13	14	Italian Grand Prix	1973-09-09	\N	http://en.wikipedia.org/wiki/1973_Italian_Grand_Prix
618	1973	14	48	Canadian Grand Prix	1973-09-23	\N	http://en.wikipedia.org/wiki/1973_Canadian_Grand_Prix
619	1973	15	46	United States Grand Prix	1973-10-07	\N	http://en.wikipedia.org/wiki/1973_United_States_Grand_Prix
620	1972	1	25	Argentine Grand Prix	1972-01-23	\N	http://en.wikipedia.org/wiki/1972_Argentine_Grand_Prix
621	1972	2	30	South African Grand Prix	1972-03-04	\N	http://en.wikipedia.org/wiki/1972_South_African_Grand_Prix
622	1972	3	45	Spanish Grand Prix	1972-05-01	\N	http://en.wikipedia.org/wiki/1972_Spanish_Grand_Prix
623	1972	4	6	Monaco Grand Prix	1972-05-14	\N	http://en.wikipedia.org/wiki/1972_Monaco_Grand_Prix
624	1972	5	50	Belgian Grand Prix	1972-06-04	\N	http://en.wikipedia.org/wiki/1972_Belgian_Grand_Prix
625	1972	6	51	French Grand Prix	1972-07-02	\N	http://en.wikipedia.org/wiki/1972_French_Grand_Prix
626	1972	7	38	British Grand Prix	1972-07-15	\N	http://en.wikipedia.org/wiki/1972_British_Grand_Prix
627	1972	8	20	German Grand Prix	1972-07-30	\N	http://en.wikipedia.org/wiki/1972_German_Grand_Prix
628	1972	9	23	Austrian Grand Prix	1972-08-13	\N	http://en.wikipedia.org/wiki/1972_Austrian_Grand_Prix
629	1972	10	14	Italian Grand Prix	1972-09-10	\N	http://en.wikipedia.org/wiki/1972_Italian_Grand_Prix
630	1972	11	48	Canadian Grand Prix	1972-09-24	\N	http://en.wikipedia.org/wiki/1972_Canadian_Grand_Prix
631	1972	12	46	United States Grand Prix	1972-10-08	\N	http://en.wikipedia.org/wiki/1972_United_States_Grand_Prix
632	1971	1	30	South African Grand Prix	1971-03-06	\N	http://en.wikipedia.org/wiki/1971_South_African_Grand_Prix
633	1971	2	49	Spanish Grand Prix	1971-04-18	\N	http://en.wikipedia.org/wiki/1971_Spanish_Grand_Prix
634	1971	3	6	Monaco Grand Prix	1971-05-23	\N	http://en.wikipedia.org/wiki/1971_Monaco_Grand_Prix
635	1971	4	39	Dutch Grand Prix	1971-06-20	\N	http://en.wikipedia.org/wiki/1971_Dutch_Grand_Prix
636	1971	5	34	French Grand Prix	1971-07-04	\N	http://en.wikipedia.org/wiki/1971_French_Grand_Prix
637	1971	6	9	British Grand Prix	1971-07-17	\N	http://en.wikipedia.org/wiki/1971_British_Grand_Prix
638	1971	7	20	German Grand Prix	1971-08-01	\N	http://en.wikipedia.org/wiki/1971_German_Grand_Prix
639	1971	8	23	Austrian Grand Prix	1971-08-15	\N	http://en.wikipedia.org/wiki/1971_Austrian_Grand_Prix
640	1971	9	14	Italian Grand Prix	1971-09-05	\N	http://en.wikipedia.org/wiki/1971_Italian_Grand_Prix
641	1971	10	48	Canadian Grand Prix	1971-09-19	\N	http://en.wikipedia.org/wiki/1971_Canadian_Grand_Prix
642	1971	11	46	United States Grand Prix	1971-10-03	\N	http://en.wikipedia.org/wiki/1971_United_States_Grand_Prix
643	1970	1	30	South African Grand Prix	1970-03-07	\N	http://en.wikipedia.org/wiki/1970_South_African_Grand_Prix
644	1970	2	45	Spanish Grand Prix	1970-04-19	\N	http://en.wikipedia.org/wiki/1970_Spanish_Grand_Prix
645	1970	3	6	Monaco Grand Prix	1970-05-10	\N	http://en.wikipedia.org/wiki/1970_Monaco_Grand_Prix
646	1970	4	13	Belgian Grand Prix	1970-06-07	\N	http://en.wikipedia.org/wiki/1970_Belgian_Grand_Prix
647	1970	5	39	Dutch Grand Prix	1970-06-21	\N	http://en.wikipedia.org/wiki/1970_Dutch_Grand_Prix
648	1970	6	51	French Grand Prix	1970-07-05	\N	http://en.wikipedia.org/wiki/1970_French_Grand_Prix
649	1970	7	38	British Grand Prix	1970-07-18	\N	http://en.wikipedia.org/wiki/1970_British_Grand_Prix
650	1970	8	10	German Grand Prix	1970-08-02	\N	http://en.wikipedia.org/wiki/1970_German_Grand_Prix
651	1970	9	23	Austrian Grand Prix	1970-08-16	\N	http://en.wikipedia.org/wiki/1970_Austrian_Grand_Prix
652	1970	10	14	Italian Grand Prix	1970-09-06	\N	http://en.wikipedia.org/wiki/1970_Italian_Grand_Prix
653	1970	11	52	Canadian Grand Prix	1970-09-20	\N	http://en.wikipedia.org/wiki/1970_Canadian_Grand_Prix
654	1970	12	46	United States Grand Prix	1970-10-04	\N	http://en.wikipedia.org/wiki/1970_United_States_Grand_Prix
655	1970	13	32	Mexican Grand Prix	1970-10-25	\N	http://en.wikipedia.org/wiki/1970_Mexican_Grand_Prix
656	1969	1	30	South African Grand Prix	1969-03-01	\N	http://en.wikipedia.org/wiki/1969_South_African_Grand_Prix
657	1969	2	49	Spanish Grand Prix	1969-05-04	\N	http://en.wikipedia.org/wiki/1969_Spanish_Grand_Prix
658	1969	3	6	Monaco Grand Prix	1969-05-18	\N	http://en.wikipedia.org/wiki/1969_Monaco_Grand_Prix
659	1969	4	39	Dutch Grand Prix	1969-06-21	\N	http://en.wikipedia.org/wiki/1969_Dutch_Grand_Prix
660	1969	5	51	French Grand Prix	1969-07-06	\N	http://en.wikipedia.org/wiki/1969_French_Grand_Prix
661	1969	6	9	British Grand Prix	1969-07-19	\N	http://en.wikipedia.org/wiki/1969_British_Grand_Prix
662	1969	7	20	German Grand Prix	1969-08-03	\N	http://en.wikipedia.org/wiki/1969_German_Grand_Prix
663	1969	8	14	Italian Grand Prix	1969-09-07	\N	http://en.wikipedia.org/wiki/1969_Italian_Grand_Prix
664	1969	9	48	Canadian Grand Prix	1969-09-20	\N	http://en.wikipedia.org/wiki/1969_Canadian_Grand_Prix
665	1969	10	46	United States Grand Prix	1969-10-05	\N	http://en.wikipedia.org/wiki/1969_United_States_Grand_Prix
666	1969	11	32	Mexican Grand Prix	1969-10-19	\N	http://en.wikipedia.org/wiki/1969_Mexican_Grand_Prix
667	1968	1	30	South African Grand Prix	1968-01-01	\N	http://en.wikipedia.org/wiki/1968_South_African_Grand_Prix
668	1968	2	45	Spanish Grand Prix	1968-05-12	\N	http://en.wikipedia.org/wiki/1968_Spanish_Grand_Prix
669	1968	3	6	Monaco Grand Prix	1968-05-26	\N	http://en.wikipedia.org/wiki/1968_Monaco_Grand_Prix
670	1968	4	13	Belgian Grand Prix	1968-06-09	\N	http://en.wikipedia.org/wiki/1968_Belgian_Grand_Prix
671	1968	5	39	Dutch Grand Prix	1968-06-23	\N	http://en.wikipedia.org/wiki/1968_Dutch_Grand_Prix
672	1968	6	53	French Grand Prix	1968-07-07	\N	http://en.wikipedia.org/wiki/1968_French_Grand_Prix
673	1968	7	38	British Grand Prix	1968-07-20	\N	http://en.wikipedia.org/wiki/1968_British_Grand_Prix
674	1968	8	20	German Grand Prix	1968-08-04	\N	http://en.wikipedia.org/wiki/1968_German_Grand_Prix
675	1968	9	14	Italian Grand Prix	1968-09-08	\N	http://en.wikipedia.org/wiki/1968_Italian_Grand_Prix
676	1968	10	52	Canadian Grand Prix	1968-09-22	\N	http://en.wikipedia.org/wiki/1968_Canadian_Grand_Prix
677	1968	11	46	United States Grand Prix	1968-10-06	\N	http://en.wikipedia.org/wiki/1968_United_States_Grand_Prix
678	1968	12	32	Mexican Grand Prix	1968-11-03	\N	http://en.wikipedia.org/wiki/1968_Mexican_Grand_Prix
679	1967	1	30	South African Grand Prix	1967-01-02	\N	http://en.wikipedia.org/wiki/1967_South_African_Grand_Prix
680	1967	2	6	Monaco Grand Prix	1967-05-07	\N	http://en.wikipedia.org/wiki/1967_Monaco_Grand_Prix
681	1967	3	39	Dutch Grand Prix	1967-06-04	\N	http://en.wikipedia.org/wiki/1967_Dutch_Grand_Prix
682	1967	4	13	Belgian Grand Prix	1967-06-18	\N	http://en.wikipedia.org/wiki/1967_Belgian_Grand_Prix
683	1967	5	54	French Grand Prix	1967-07-02	\N	http://en.wikipedia.org/wiki/1967_French_Grand_Prix
684	1967	6	9	British Grand Prix	1967-07-15	\N	http://en.wikipedia.org/wiki/1967_British_Grand_Prix
685	1967	7	20	German Grand Prix	1967-08-06	\N	http://en.wikipedia.org/wiki/1967_German_Grand_Prix
686	1967	8	48	Canadian Grand Prix	1967-08-27	\N	http://en.wikipedia.org/wiki/1967_Canadian_Grand_Prix
687	1967	9	14	Italian Grand Prix	1967-09-10	\N	http://en.wikipedia.org/wiki/1967_Italian_Grand_Prix
688	1967	10	46	United States Grand Prix	1967-10-01	\N	http://en.wikipedia.org/wiki/1967_United_States_Grand_Prix
689	1967	11	32	Mexican Grand Prix	1967-10-22	\N	http://en.wikipedia.org/wiki/1967_Mexican_Grand_Prix
690	1966	1	6	Monaco Grand Prix	1966-05-22	\N	http://en.wikipedia.org/wiki/1966_Monaco_Grand_Prix
691	1966	2	13	Belgian Grand Prix	1966-06-12	\N	http://en.wikipedia.org/wiki/1966_Belgian_Grand_Prix
692	1966	3	55	French Grand Prix	1966-07-03	\N	http://en.wikipedia.org/wiki/1966_French_Grand_Prix
693	1966	4	38	British Grand Prix	1966-07-16	\N	http://en.wikipedia.org/wiki/1966_British_Grand_Prix
694	1966	5	39	Dutch Grand Prix	1966-07-24	\N	http://en.wikipedia.org/wiki/1966_Dutch_Grand_Prix
695	1966	6	20	German Grand Prix	1966-08-07	\N	http://en.wikipedia.org/wiki/1966_German_Grand_Prix
696	1966	7	14	Italian Grand Prix	1966-09-04	\N	http://en.wikipedia.org/wiki/1966_Italian_Grand_Prix
697	1966	8	46	United States Grand Prix	1966-10-02	\N	http://en.wikipedia.org/wiki/1966_United_States_Grand_Prix
698	1966	9	32	Mexican Grand Prix	1966-10-23	\N	http://en.wikipedia.org/wiki/1966_Mexican_Grand_Prix
699	1965	1	56	South African Grand Prix	1965-01-01	\N	http://en.wikipedia.org/wiki/1965_South_African_Grand_Prix
700	1965	2	6	Monaco Grand Prix	1965-05-30	\N	http://en.wikipedia.org/wiki/1965_Monaco_Grand_Prix
701	1965	3	13	Belgian Grand Prix	1965-06-13	\N	http://en.wikipedia.org/wiki/1965_Belgian_Grand_Prix
702	1965	4	51	French Grand Prix	1965-06-27	\N	http://en.wikipedia.org/wiki/1965_French_Grand_Prix
703	1965	5	9	British Grand Prix	1965-07-10	\N	http://en.wikipedia.org/wiki/1965_British_Grand_Prix
704	1965	6	39	Dutch Grand Prix	1965-07-18	\N	http://en.wikipedia.org/wiki/1965_Dutch_Grand_Prix
705	1965	7	20	German Grand Prix	1965-08-01	\N	http://en.wikipedia.org/wiki/1965_German_Grand_Prix
706	1965	8	14	Italian Grand Prix	1965-09-12	\N	http://en.wikipedia.org/wiki/1965_Italian_Grand_Prix
707	1965	9	46	United States Grand Prix	1965-10-03	\N	http://en.wikipedia.org/wiki/1965_United_States_Grand_Prix
708	1965	10	32	Mexican Grand Prix	1965-10-24	\N	http://en.wikipedia.org/wiki/1965_Mexican_Grand_Prix
709	1964	1	6	Monaco Grand Prix	1964-05-10	\N	http://en.wikipedia.org/wiki/1964_Monaco_Grand_Prix
710	1964	2	39	Dutch Grand Prix	1964-05-24	\N	http://en.wikipedia.org/wiki/1964_Dutch_Grand_Prix
711	1964	3	13	Belgian Grand Prix	1964-06-14	\N	http://en.wikipedia.org/wiki/1964_Belgian_Grand_Prix
712	1964	4	53	French Grand Prix	1964-06-28	\N	http://en.wikipedia.org/wiki/1964_French_Grand_Prix
713	1964	5	38	British Grand Prix	1964-07-11	\N	http://en.wikipedia.org/wiki/1964_British_Grand_Prix
714	1964	6	20	German Grand Prix	1964-08-02	\N	http://en.wikipedia.org/wiki/1964_German_Grand_Prix
715	1964	7	57	Austrian Grand Prix	1964-08-23	\N	http://en.wikipedia.org/wiki/1964_Austrian_Grand_Prix
716	1964	8	14	Italian Grand Prix	1964-09-06	\N	http://en.wikipedia.org/wiki/1964_Italian_Grand_Prix
717	1964	9	46	United States Grand Prix	1964-10-04	\N	http://en.wikipedia.org/wiki/1964_United_States_Grand_Prix
718	1964	10	32	Mexican Grand Prix	1964-10-25	\N	http://en.wikipedia.org/wiki/1964_Mexican_Grand_Prix
719	1963	1	6	Monaco Grand Prix	1963-05-26	\N	http://en.wikipedia.org/wiki/1963_Monaco_Grand_Prix
720	1963	2	13	Belgian Grand Prix	1963-06-09	\N	http://en.wikipedia.org/wiki/1963_Belgian_Grand_Prix
721	1963	3	39	Dutch Grand Prix	1963-06-23	\N	http://en.wikipedia.org/wiki/1963_Dutch_Grand_Prix
722	1963	4	55	French Grand Prix	1963-06-30	\N	http://en.wikipedia.org/wiki/1963_French_Grand_Prix
723	1963	5	9	British Grand Prix	1963-07-20	\N	http://en.wikipedia.org/wiki/1963_British_Grand_Prix
724	1963	6	20	German Grand Prix	1963-08-04	\N	http://en.wikipedia.org/wiki/1963_German_Grand_Prix
725	1963	7	14	Italian Grand Prix	1963-09-08	\N	http://en.wikipedia.org/wiki/1963_Italian_Grand_Prix
726	1963	8	46	United States Grand Prix	1963-10-06	\N	http://en.wikipedia.org/wiki/1963_United_States_Grand_Prix
727	1963	9	32	Mexican Grand Prix	1963-10-27	\N	http://en.wikipedia.org/wiki/1963_Mexican_Grand_Prix
728	1963	10	56	South African Grand Prix	1963-12-28	\N	http://en.wikipedia.org/wiki/1963_South_African_Grand_Prix
729	1962	1	39	Dutch Grand Prix	1962-05-20	\N	http://en.wikipedia.org/wiki/1962_Dutch_Grand_Prix
730	1962	2	6	Monaco Grand Prix	1962-06-03	\N	http://en.wikipedia.org/wiki/1962_Monaco_Grand_Prix
731	1962	3	13	Belgian Grand Prix	1962-06-17	\N	http://en.wikipedia.org/wiki/1962_Belgian_Grand_Prix
732	1962	4	53	French Grand Prix	1962-07-08	\N	http://en.wikipedia.org/wiki/1962_French_Grand_Prix
733	1962	5	58	British Grand Prix	1962-07-21	\N	http://en.wikipedia.org/wiki/1962_British_Grand_Prix
734	1962	6	20	German Grand Prix	1962-08-05	\N	http://en.wikipedia.org/wiki/1962_German_Grand_Prix
735	1962	7	14	Italian Grand Prix	1962-09-16	\N	http://en.wikipedia.org/wiki/1962_Italian_Grand_Prix
736	1962	8	46	United States Grand Prix	1962-10-07	\N	http://en.wikipedia.org/wiki/1962_United_States_Grand_Prix
737	1962	9	56	South African Grand Prix	1962-12-29	\N	http://en.wikipedia.org/wiki/1962_South_African_Grand_Prix
738	1961	1	6	Monaco Grand Prix	1961-05-14	\N	http://en.wikipedia.org/wiki/1961_Monaco_Grand_Prix
739	1961	2	39	Dutch Grand Prix	1961-05-22	\N	http://en.wikipedia.org/wiki/1961_Dutch_Grand_Prix
740	1961	3	13	Belgian Grand Prix	1961-06-18	\N	http://en.wikipedia.org/wiki/1961_Belgian_Grand_Prix
741	1961	4	55	French Grand Prix	1961-07-02	\N	http://en.wikipedia.org/wiki/1961_French_Grand_Prix
742	1961	5	58	British Grand Prix	1961-07-15	\N	http://en.wikipedia.org/wiki/1961_British_Grand_Prix
743	1961	6	20	German Grand Prix	1961-08-06	\N	http://en.wikipedia.org/wiki/1961_German_Grand_Prix
744	1961	7	14	Italian Grand Prix	1961-09-10	\N	http://en.wikipedia.org/wiki/1961_Italian_Grand_Prix
745	1961	8	46	United States Grand Prix	1961-10-08	\N	http://en.wikipedia.org/wiki/1961_United_States_Grand_Prix
746	1960	1	25	Argentine Grand Prix	1960-02-07	\N	http://en.wikipedia.org/wiki/1960_Argentine_Grand_Prix
747	1960	2	6	Monaco Grand Prix	1960-05-29	\N	http://en.wikipedia.org/wiki/1960_Monaco_Grand_Prix
748	1960	3	19	Indianapolis 500	1960-05-30	\N	http://en.wikipedia.org/wiki/1960_Indianapolis_500
749	1960	4	39	Dutch Grand Prix	1960-06-06	\N	http://en.wikipedia.org/wiki/1960_Dutch_Grand_Prix
750	1960	5	13	Belgian Grand Prix	1960-06-19	\N	http://en.wikipedia.org/wiki/1960_Belgian_Grand_Prix
751	1960	6	55	French Grand Prix	1960-07-03	\N	http://en.wikipedia.org/wiki/1960_French_Grand_Prix
752	1960	7	9	British Grand Prix	1960-07-16	\N	http://en.wikipedia.org/wiki/1960_British_Grand_Prix
753	1960	8	59	Portuguese Grand Prix	1960-08-14	\N	http://en.wikipedia.org/wiki/1960_Portuguese_Grand_Prix
754	1960	9	14	Italian Grand Prix	1960-09-04	\N	http://en.wikipedia.org/wiki/1960_Italian_Grand_Prix
755	1960	10	60	United States Grand Prix	1960-11-20	\N	http://en.wikipedia.org/wiki/1960_United_States_Grand_Prix
756	1959	1	6	Monaco Grand Prix	1959-05-10	\N	http://en.wikipedia.org/wiki/1959_Monaco_Grand_Prix
757	1959	2	19	Indianapolis 500	1959-05-30	\N	http://en.wikipedia.org/wiki/1959_Indianapolis_500
758	1959	3	39	Dutch Grand Prix	1959-05-31	\N	http://en.wikipedia.org/wiki/1959_Dutch_Grand_Prix
759	1959	4	55	French Grand Prix	1959-07-05	\N	http://en.wikipedia.org/wiki/1959_French_Grand_Prix
760	1959	5	58	British Grand Prix	1959-07-18	\N	http://en.wikipedia.org/wiki/1959_British_Grand_Prix
761	1959	6	61	German Grand Prix	1959-08-02	\N	http://en.wikipedia.org/wiki/1959_German_Grand_Prix
762	1959	7	62	Portuguese Grand Prix	1959-08-23	\N	http://en.wikipedia.org/wiki/1959_Portuguese_Grand_Prix
763	1959	8	14	Italian Grand Prix	1959-09-13	\N	http://en.wikipedia.org/wiki/1959_Italian_Grand_Prix
764	1959	9	63	United States Grand Prix	1959-12-12	\N	http://en.wikipedia.org/wiki/1959_United_States_Grand_Prix
765	1958	1	25	Argentine Grand Prix	1958-01-19	\N	http://en.wikipedia.org/wiki/1958_Argentine_Grand_Prix
766	1958	2	6	Monaco Grand Prix	1958-05-18	\N	http://en.wikipedia.org/wiki/1958_Monaco_Grand_Prix
767	1958	3	39	Dutch Grand Prix	1958-05-26	\N	http://en.wikipedia.org/wiki/1958_Dutch_Grand_Prix
768	1958	4	19	Indianapolis 500	1958-05-30	\N	http://en.wikipedia.org/wiki/1958_Indianapolis_500
769	1958	5	13	Belgian Grand Prix	1958-06-15	\N	http://en.wikipedia.org/wiki/1958_Belgian_Grand_Prix
770	1958	6	55	French Grand Prix	1958-07-06	\N	http://en.wikipedia.org/wiki/1958_French_Grand_Prix
771	1958	7	9	British Grand Prix	1958-07-19	\N	http://en.wikipedia.org/wiki/1958_British_Grand_Prix
772	1958	8	20	German Grand Prix	1958-08-03	\N	http://en.wikipedia.org/wiki/1958_German_Grand_Prix
773	1958	9	59	Portuguese Grand Prix	1958-08-24	\N	http://en.wikipedia.org/wiki/1958_Portuguese_Grand_Prix
774	1958	10	14	Italian Grand Prix	1958-09-07	\N	http://en.wikipedia.org/wiki/1958_Italian_Grand_Prix
775	1958	11	64	Moroccan Grand Prix	1958-10-19	\N	http://en.wikipedia.org/wiki/1958_Moroccan_Grand_Prix
776	1957	1	25	Argentine Grand Prix	1957-01-13	\N	http://en.wikipedia.org/wiki/1957_Argentine_Grand_Prix
777	1957	2	6	Monaco Grand Prix	1957-05-19	\N	http://en.wikipedia.org/wiki/1957_Monaco_Grand_Prix
778	1957	3	19	Indianapolis 500	1957-05-30	\N	http://en.wikipedia.org/wiki/1957_Indianapolis_500
779	1957	4	53	French Grand Prix	1957-07-07	\N	http://en.wikipedia.org/wiki/1957_French_Grand_Prix
780	1957	5	58	British Grand Prix	1957-07-20	\N	http://en.wikipedia.org/wiki/1957_British_Grand_Prix
781	1957	6	20	German Grand Prix	1957-08-04	\N	http://en.wikipedia.org/wiki/1957_German_Grand_Prix
782	1957	7	65	Pescara Grand Prix	1957-08-18	\N	http://en.wikipedia.org/wiki/1957_Pescara_Grand_Prix
783	1957	8	14	Italian Grand Prix	1957-09-08	\N	http://en.wikipedia.org/wiki/1957_Italian_Grand_Prix
784	1956	1	25	Argentine Grand Prix	1956-01-22	\N	http://en.wikipedia.org/wiki/1956_Argentine_Grand_Prix
785	1956	2	6	Monaco Grand Prix	1956-05-13	\N	http://en.wikipedia.org/wiki/1956_Monaco_Grand_Prix
786	1956	3	19	Indianapolis 500	1956-05-30	\N	http://en.wikipedia.org/wiki/1956_Indianapolis_500
787	1956	4	13	Belgian Grand Prix	1956-06-03	\N	http://en.wikipedia.org/wiki/1956_Belgian_Grand_Prix
788	1956	5	55	French Grand Prix	1956-07-01	\N	http://en.wikipedia.org/wiki/1956_French_Grand_Prix
789	1956	6	9	British Grand Prix	1956-07-14	\N	http://en.wikipedia.org/wiki/1956_British_Grand_Prix
790	1956	7	20	German Grand Prix	1956-08-05	\N	http://en.wikipedia.org/wiki/1956_German_Grand_Prix
791	1956	8	14	Italian Grand Prix	1956-09-02	\N	http://en.wikipedia.org/wiki/1956_Italian_Grand_Prix
792	1955	1	25	Argentine Grand Prix	1955-01-16	\N	http://en.wikipedia.org/wiki/1955_Argentine_Grand_Prix
793	1955	2	6	Monaco Grand Prix	1955-05-22	\N	http://en.wikipedia.org/wiki/1955_Monaco_Grand_Prix
794	1955	3	19	Indianapolis 500	1955-05-30	\N	http://en.wikipedia.org/wiki/1955_Indianapolis_500
795	1955	4	13	Belgian Grand Prix	1955-06-05	\N	http://en.wikipedia.org/wiki/1955_Belgian_Grand_Prix
796	1955	5	39	Dutch Grand Prix	1955-06-19	\N	http://en.wikipedia.org/wiki/1955_Dutch_Grand_Prix
797	1955	6	58	British Grand Prix	1955-07-16	\N	http://en.wikipedia.org/wiki/1955_British_Grand_Prix
798	1955	7	14	Italian Grand Prix	1955-09-11	\N	http://en.wikipedia.org/wiki/1955_Italian_Grand_Prix
799	1954	1	25	Argentine Grand Prix	1954-01-17	\N	http://en.wikipedia.org/wiki/1954_Argentine_Grand_Prix
800	1954	2	19	Indianapolis 500	1954-05-31	\N	http://en.wikipedia.org/wiki/1954_Indianapolis_500
801	1954	3	13	Belgian Grand Prix	1954-06-20	\N	http://en.wikipedia.org/wiki/1954_Belgian_Grand_Prix
802	1954	4	55	French Grand Prix	1954-07-04	\N	http://en.wikipedia.org/wiki/1954_French_Grand_Prix
803	1954	5	9	British Grand Prix	1954-07-17	\N	http://en.wikipedia.org/wiki/1954_British_Grand_Prix
804	1954	6	20	German Grand Prix	1954-08-01	\N	http://en.wikipedia.org/wiki/1954_German_Grand_Prix
805	1954	7	66	Swiss Grand Prix	1954-08-22	\N	http://en.wikipedia.org/wiki/1954_Swiss_Grand_Prix
806	1954	8	14	Italian Grand Prix	1954-09-05	\N	http://en.wikipedia.org/wiki/1954_Italian_Grand_Prix
807	1954	9	67	Spanish Grand Prix	1954-10-24	\N	http://en.wikipedia.org/wiki/1954_Spanish_Grand_Prix
808	1953	1	25	Argentine Grand Prix	1953-01-18	\N	http://en.wikipedia.org/wiki/1953_Argentine_Grand_Prix
809	1953	2	19	Indianapolis 500	1953-05-30	\N	http://en.wikipedia.org/wiki/1953_Indianapolis_500
810	1953	3	39	Dutch Grand Prix	1953-06-07	\N	http://en.wikipedia.org/wiki/1953_Dutch_Grand_Prix
811	1953	4	13	Belgian Grand Prix	1953-06-21	\N	http://en.wikipedia.org/wiki/1953_Belgian_Grand_Prix
812	1953	5	55	French Grand Prix	1953-07-05	\N	http://en.wikipedia.org/wiki/1953_French_Grand_Prix
813	1953	6	9	British Grand Prix	1953-07-18	\N	http://en.wikipedia.org/wiki/1953_British_Grand_Prix
814	1953	7	20	German Grand Prix	1953-08-02	\N	http://en.wikipedia.org/wiki/1953_German_Grand_Prix
815	1953	8	66	Swiss Grand Prix	1953-08-23	\N	http://en.wikipedia.org/wiki/1953_Swiss_Grand_Prix
816	1953	9	14	Italian Grand Prix	1953-09-13	\N	http://en.wikipedia.org/wiki/1953_Italian_Grand_Prix
817	1952	1	66	Swiss Grand Prix	1952-05-18	\N	http://en.wikipedia.org/wiki/1952_Swiss_Grand_Prix
818	1952	2	19	Indianapolis 500	1952-05-30	\N	http://en.wikipedia.org/wiki/1952_Indianapolis_500
819	1952	3	13	Belgian Grand Prix	1952-06-22	\N	http://en.wikipedia.org/wiki/1952_Belgian_Grand_Prix
820	1952	4	53	French Grand Prix	1952-07-06	\N	http://en.wikipedia.org/wiki/1952_French_Grand_Prix
821	1952	5	9	British Grand Prix	1952-07-19	\N	http://en.wikipedia.org/wiki/1952_British_Grand_Prix
822	1952	6	20	German Grand Prix	1952-08-03	\N	http://en.wikipedia.org/wiki/1952_German_Grand_Prix
823	1952	7	39	Dutch Grand Prix	1952-08-17	\N	http://en.wikipedia.org/wiki/1952_Dutch_Grand_Prix
824	1952	8	14	Italian Grand Prix	1952-09-07	\N	http://en.wikipedia.org/wiki/1952_Italian_Grand_Prix
825	1951	1	66	Swiss Grand Prix	1951-05-27	\N	http://en.wikipedia.org/wiki/1951_Swiss_Grand_Prix
826	1951	2	19	Indianapolis 500	1951-05-30	\N	http://en.wikipedia.org/wiki/1951_Indianapolis_500
827	1951	3	13	Belgian Grand Prix	1951-06-17	\N	http://en.wikipedia.org/wiki/1951_Belgian_Grand_Prix
828	1951	4	55	French Grand Prix	1951-07-01	\N	http://en.wikipedia.org/wiki/1951_French_Grand_Prix
829	1951	5	9	British Grand Prix	1951-07-14	\N	http://en.wikipedia.org/wiki/1951_British_Grand_Prix
830	1951	6	20	German Grand Prix	1951-07-29	\N	http://en.wikipedia.org/wiki/1951_German_Grand_Prix
831	1951	7	14	Italian Grand Prix	1951-09-16	\N	http://en.wikipedia.org/wiki/1951_Italian_Grand_Prix
832	1951	8	67	Spanish Grand Prix	1951-10-28	\N	http://en.wikipedia.org/wiki/1951_Spanish_Grand_Prix
833	1950	1	9	British Grand Prix	1950-05-13	\N	http://en.wikipedia.org/wiki/1950_British_Grand_Prix
834	1950	2	6	Monaco Grand Prix	1950-05-21	\N	http://en.wikipedia.org/wiki/1950_Monaco_Grand_Prix
835	1950	3	19	Indianapolis 500	1950-05-30	\N	http://en.wikipedia.org/wiki/1950_Indianapolis_500
836	1950	4	66	Swiss Grand Prix	1950-06-04	\N	http://en.wikipedia.org/wiki/1950_Swiss_Grand_Prix
837	1950	5	13	Belgian Grand Prix	1950-06-18	\N	http://en.wikipedia.org/wiki/1950_Belgian_Grand_Prix
838	1950	6	55	French Grand Prix	1950-07-02	\N	http://en.wikipedia.org/wiki/1950_French_Grand_Prix
839	1950	7	14	Italian Grand Prix	1950-09-03	\N	http://en.wikipedia.org/wiki/1950_Italian_Grand_Prix
841	2011	1	1	Australian Grand Prix	2011-03-27	06:00:00	http://en.wikipedia.org/wiki/2011_Australian_Grand_Prix
842	2011	2	2	Malaysian Grand Prix	2011-04-10	08:00:00	http://en.wikipedia.org/wiki/2011_Malaysian_Grand_Prix
843	2011	3	17	Chinese Grand Prix	2011-04-17	07:00:00	http://en.wikipedia.org/wiki/2011_Chinese_Grand_Prix
844	2011	4	5	Turkish Grand Prix	2011-05-08	12:00:00	http://en.wikipedia.org/wiki/2011_Turkish_Grand_Prix
845	2011	5	4	Spanish Grand Prix	2011-05-22	12:00:00	http://en.wikipedia.org/wiki/2011_Spanish_Grand_Prix
846	2011	6	6	Monaco Grand Prix	2011-05-29	12:00:00	http://en.wikipedia.org/wiki/2011_Monaco_Grand_Prix
847	2011	7	7	Canadian Grand Prix	2011-06-12	17:00:00	http://en.wikipedia.org/wiki/2011_Canadian_Grand_Prix
848	2011	8	12	European Grand Prix	2011-06-26	12:00:00	http://en.wikipedia.org/wiki/2011_European_Grand_Prix
849	2011	9	9	British Grand Prix	2011-07-10	12:00:00	http://en.wikipedia.org/wiki/2011_British_Grand_Prix
850	2011	10	20	German Grand Prix	2011-07-24	12:00:00	http://en.wikipedia.org/wiki/2011_German_Grand_Prix
851	2011	11	11	Hungarian Grand Prix	2011-07-31	12:00:00	http://en.wikipedia.org/wiki/2011_Hungarian_Grand_Prix
852	2011	12	13	Belgian Grand Prix	2011-08-28	12:00:00	http://en.wikipedia.org/wiki/2011_Belgian_Grand_Prix
853	2011	13	14	Italian Grand Prix	2011-09-11	12:00:00	http://en.wikipedia.org/wiki/2011_Italian_Grand_Prix
854	2011	14	15	Singapore Grand Prix	2011-09-25	12:00:00	http://en.wikipedia.org/wiki/2011_Singapore_Grand_Prix
855	2011	15	22	Japanese Grand Prix	2011-10-09	06:00:00	http://en.wikipedia.org/wiki/2011_Japanese_Grand_Prix
856	2011	16	35	Korean Grand Prix	2011-10-16	06:00:00	http://en.wikipedia.org/wiki/2011_Korean_Grand_Prix
857	2011	17	68	Indian Grand Prix	2011-10-30	09:30:00	http://en.wikipedia.org/wiki/2011_Indian_Grand_Prix
858	2011	18	24	Abu Dhabi Grand Prix	2011-11-13	13:00:00	http://en.wikipedia.org/wiki/2011_Abu_Dhabi_Grand_Prix
859	2011	19	18	Brazilian Grand Prix	2011-11-27	16:00:00	http://en.wikipedia.org/wiki/2011_Brazilian_Grand_Prix
860	2012	1	1	Australian Grand Prix	2012-03-18	06:00:00	http://en.wikipedia.org/wiki/2012_Australian_Grand_Prix
861	2012	2	2	Malaysian Grand Prix	2012-03-25	08:00:00	http://en.wikipedia.org/wiki/2012_Malaysian_Grand_Prix
862	2012	3	17	Chinese Grand Prix	2012-04-15	07:00:00	http://en.wikipedia.org/wiki/2012_Chinese_Grand_Prix
863	2012	4	3	Bahrain Grand Prix	2012-04-22	12:00:00	http://en.wikipedia.org/wiki/2012_Bahrain_Grand_Prix
864	2012	5	4	Spanish Grand Prix	2012-05-13	12:00:00	http://en.wikipedia.org/wiki/2012_Spanish_Grand_Prix
865	2012	6	6	Monaco Grand Prix	2012-05-27	12:00:00	http://en.wikipedia.org/wiki/2012_Monaco_Grand_Prix
866	2012	7	7	Canadian Grand Prix	2012-06-10	18:00:00	http://en.wikipedia.org/wiki/2012_Canadian_Grand_Prix
867	2012	8	12	European Grand Prix	2012-06-24	12:00:00	http://en.wikipedia.org/wiki/2012_European_Grand_Prix
868	2012	9	9	British Grand Prix	2012-07-08	12:00:00	http://en.wikipedia.org/wiki/2012_British_Grand_Prix
869	2012	10	10	German Grand Prix	2012-07-22	12:00:00	http://en.wikipedia.org/wiki/2012_German_Grand_Prix
870	2012	11	11	Hungarian Grand Prix	2012-07-29	12:00:00	http://en.wikipedia.org/wiki/2012_Hungarian_Grand_Prix
871	2012	12	13	Belgian Grand Prix	2012-09-02	12:00:00	http://en.wikipedia.org/wiki/2012_Belgian_Grand_Prix
872	2012	13	14	Italian Grand Prix	2012-09-09	12:00:00	http://en.wikipedia.org/wiki/2012_Italian_Grand_Prix
873	2012	14	15	Singapore Grand Prix	2012-09-23	12:00:00	http://en.wikipedia.org/wiki/2012_Singapore_Grand_Prix
874	2012	15	22	Japanese Grand Prix	2012-10-07	06:00:00	http://en.wikipedia.org/wiki/2012_Japanese_Grand_Prix
875	2012	16	35	Korean Grand Prix	2012-10-14	06:00:00	http://en.wikipedia.org/wiki/2012_Korean_Grand_Prix
876	2012	17	68	Indian Grand Prix	2012-10-28	09:30:00	http://en.wikipedia.org/wiki/2012_Indian_Grand_Prix
877	2012	18	24	Abu Dhabi Grand Prix	2012-11-04	13:00:00	http://en.wikipedia.org/wiki/2012_Abu_Dhabi_Grand_Prix
878	2012	19	69	United States Grand Prix	2012-11-18	19:00:00	http://en.wikipedia.org/wiki/2012_United_States_Grand_Prix
879	2012	20	18	Brazilian Grand Prix	2012-11-25	16:00:00	http://en.wikipedia.org/wiki/2012_Brazilian_Grand_Prix
880	2013	1	1	Australian Grand Prix	2013-03-17	06:00:00	http://en.wikipedia.org/wiki/2013_Australian_Grand_Prix
881	2013	2	2	Malaysian Grand Prix	2013-03-24	08:00:00	http://en.wikipedia.org/wiki/2013_Malaysian_Grand_Prix
882	2013	3	17	Chinese Grand Prix	2013-04-14	07:00:00	http://en.wikipedia.org/wiki/2013_Chinese_Grand_Prix
883	2013	4	3	Bahrain Grand Prix	2013-04-21	12:00:00	http://en.wikipedia.org/wiki/2013_Bahrain_Grand_Prix
884	2013	5	4	Spanish Grand Prix	2013-05-12	12:00:00	http://en.wikipedia.org/wiki/2013_Spanish_Grand_Prix
885	2013	6	6	Monaco Grand Prix	2013-05-26	12:00:00	http://en.wikipedia.org/wiki/2013_Monaco_Grand_Prix
886	2013	7	7	Canadian Grand Prix	2013-06-09	18:00:00	http://en.wikipedia.org/wiki/2013_Canadian_Grand_Prix
887	2013	8	9	British Grand Prix	2013-06-30	12:00:00	http://en.wikipedia.org/wiki/2013_British_Grand_Prix
888	2013	9	20	German Grand Prix	2013-07-07	12:00:00	http://en.wikipedia.org/wiki/2013_German_Grand_Prix
890	2013	10	11	Hungarian Grand Prix	2013-07-28	12:00:00	http://en.wikipedia.org/wiki/2013_Hungarian_Grand_Prix
891	2013	11	13	Belgian Grand Prix	2013-08-25	12:00:00	http://en.wikipedia.org/wiki/2013_Belgian_Grand_Prix
892	2013	12	14	Italian Grand Prix	2013-09-08	12:00:00	http://en.wikipedia.org/wiki/2013_Italian_Grand_Prix
893	2013	13	15	Singapore Grand Prix	2013-09-22	12:00:00	http://en.wikipedia.org/wiki/2013_Singapore_Grand_Prix
894	2013	14	35	Korean Grand Prix	2013-10-06	06:00:00	http://en.wikipedia.org/wiki/2013_Korean_Grand_Prix
895	2013	15	22	Japanese Grand Prix	2013-10-13	06:00:00	http://en.wikipedia.org/wiki/2013_Japanese_Grand_Prix
896	2013	16	68	Indian Grand Prix	2013-10-27	09:30:00	http://en.wikipedia.org/wiki/2013_Indian_Grand_Prix
897	2013	17	24	Abu Dhabi Grand Prix	2013-11-03	13:00:00	http://en.wikipedia.org/wiki/2013_Abu_Dhabi_Grand_Prix
898	2013	18	69	United States Grand Prix	2013-11-17	19:00:00	http://en.wikipedia.org/wiki/2013_United_States_Grand_Prix
899	2013	19	18	Brazilian Grand Prix	2013-11-24	16:00:00	http://en.wikipedia.org/wiki/2013_Brazilian_Grand_Prix
900	2014	1	1	Australian Grand Prix	2014-03-16	06:00:00	https://en.wikipedia.org/wiki/2014_Australian_Grand_Prix
901	2014	2	2	Malaysian Grand Prix	2014-03-30	08:00:00	https://en.wikipedia.org/wiki/2014_Malaysian_Grand_Prix
902	2014	3	3	Bahrain Grand Prix	2014-04-06	15:00:00	http://en.wikipedia.org/wiki/2014_Bahrain_Grand_Prix
903	2014	4	17	Chinese Grand Prix	2014-04-20	07:00:00	http://en.wikipedia.org/wiki/2014_Chinese_Grand_Prix
904	2014	5	4	Spanish Grand Prix	2014-05-11	12:00:00	http://en.wikipedia.org/wiki/2014_Spanish_Grand_Prix
905	2014	6	6	Monaco Grand Prix	2014-05-25	12:00:00	http://en.wikipedia.org/wiki/2014_Monaco_Grand_Prix
906	2014	7	7	Canadian Grand Prix	2014-06-08	18:00:00	http://en.wikipedia.org/wiki/2014_Canadian_Grand_Prix
907	2014	8	70	Austrian Grand Prix	2014-06-22	12:00:00	http://en.wikipedia.org/wiki/2014_Austrian_Grand_Prix
908	2014	9	9	British Grand Prix	2014-07-06	12:00:00	http://en.wikipedia.org/wiki/2014_British_Grand_Prix
909	2014	10	10	German Grand Prix	2014-07-20	12:00:00	http://en.wikipedia.org/wiki/2014_German_Grand_Prixs
910	2014	11	11	Hungarian Grand Prix	2014-07-27	12:00:00	http://en.wikipedia.org/wiki/2014_Hungarian_Grand_Prix
911	2014	12	13	Belgian Grand Prix	2014-08-24	12:00:00	http://en.wikipedia.org/wiki/2014_Belgian_Grand_Prix
912	2014	13	14	Italian Grand Prix	2014-09-07	12:00:00	http://en.wikipedia.org/wiki/2014_Italian_Grand_Prix
913	2014	14	15	Singapore Grand Prix	2014-09-21	12:00:00	http://en.wikipedia.org/wiki/2014_Singapore_Grand_Prix
914	2014	15	22	Japanese Grand Prix	2014-10-05	06:00:00	http://en.wikipedia.org/wiki/2014_Japanese_Grand_Prix
915	2014	16	71	Russian Grand Prix	2014-10-12	11:00:00	http://en.wikipedia.org/wiki/2014_Russian_Grand_Prix
916	2014	17	69	United States Grand Prix	2014-11-02	20:00:00	http://en.wikipedia.org/wiki/2014_United_States_Grand_Prix
917	2014	18	18	Brazilian Grand Prix	2014-11-09	16:00:00	http://en.wikipedia.org/wiki/2014_Brazilian_Grand_Prix
918	2014	19	24	Abu Dhabi Grand Prix	2014-11-23	13:00:00	http://en.wikipedia.org/wiki/2014_Abu_Dhabi_Grand_Prix
931	2015	6	6	Monaco Grand Prix	2015-05-24	12:00:00	http://en.wikipedia.org/wiki/2015_Monaco_Grand_Prix
932	2015	7	7	Canadian Grand Prix	2015-06-07	18:00:00	http://en.wikipedia.org/wiki/2015_Canadian_Grand_Prix
929	2015	4	3	Bahrain Grand Prix	2015-04-19	15:00:00	http://en.wikipedia.org/wiki/2015_Bahrain_Grand_Prix
930	2015	5	4	Spanish Grand Prix	2015-05-10	12:00:00	http://en.wikipedia.org/wiki/2015_Spanish_Grand_Prix
928	2015	3	17	Chinese Grand Prix	2015-04-12	06:00:00	http://en.wikipedia.org/wiki/2015_Chinese_Grand_Prix
926	2015	1	1	Australian Grand Prix	2015-03-15	05:00:00	http://en.wikipedia.org/wiki/2015_Australian_Grand_Prix
927	2015	2	2	Malaysian Grand Prix	2015-03-29	07:00:00	http://en.wikipedia.org/wiki/2015_Malaysian_Grand_Prix
933	2015	8	70	Austrian Grand Prix	2015-06-21	12:00:00	http://en.wikipedia.org/wiki/2015_Austrian_Grand_Prix
934	2015	9	9	British Grand Prix	2015-07-05	12:00:00	http://en.wikipedia.org/wiki/2015_British_Grand_Prix
936	2015	10	11	Hungarian Grand Prix	2015-07-26	12:00:00	http://en.wikipedia.org/wiki/2015_Hungarian_Grand_Prix
937	2015	11	13	Belgian Grand Prix	2015-08-23	12:00:00	http://en.wikipedia.org/wiki/2015_Belgian_Grand_Prix
938	2015	12	14	Italian Grand Prix	2015-09-06	12:00:00	http://en.wikipedia.org/wiki/2015_Italian_Grand_Prix
939	2015	13	15	Singapore Grand Prix	2015-09-20	12:00:00	https://en.wikipedia.org/wiki/2015_Singapore_Grand_Prix
940	2015	14	22	Japanese Grand Prix	2015-09-27	05:00:00	https://en.wikipedia.org/wiki/2015_Japanese_Grand_Prix
941	2015	15	71	Russian Grand Prix	2015-10-11	11:00:00	https://en.wikipedia.org/wiki/2015_Russian_Grand_Prix
942	2015	16	69	United States Grand Prix	2015-10-25	19:00:00	https://en.wikipedia.org/wiki/2015_United_States_Grand_Prix
943	2015	17	32	Mexican Grand Prix	2015-11-01	19:00:00	https://en.wikipedia.org/wiki/2015_Mexican_Grand_Prix
944	2015	18	18	Brazilian Grand Prix	2015-11-15	16:00:00	https://en.wikipedia.org/wiki/2015_Brazilian_Grand_Prix
945	2015	19	24	Abu Dhabi Grand Prix	2015-11-29	13:00:00	https://en.wikipedia.org/wiki/2015_Abu_Dhabi_Grand_Prix
948	2016	1	1	Australian Grand Prix	2016-03-20	05:00:00	https://en.wikipedia.org/wiki/2016_Australian_Grand_Prix
949	2016	2	3	Bahrain Grand Prix	2016-04-03	15:00:00	https://en.wikipedia.org/wiki/2016_Bahrain_Grand_Prix
950	2016	3	17	Chinese Grand Prix	2016-04-17	06:00:00	https://en.wikipedia.org/wiki/2016_Chinese_Grand_Prix
951	2016	4	71	Russian Grand Prix	2016-05-01	12:00:00	https://en.wikipedia.org/wiki/2016_Russian_Grand_Prix
952	2016	5	4	Spanish Grand Prix	2016-05-15	12:00:00	https://en.wikipedia.org/wiki/2016_Spanish_Grand_Prix
953	2016	6	6	Monaco Grand Prix	2016-05-29	12:00:00	https://en.wikipedia.org/wiki/2016_Monaco_Grand_Prix
954	2016	7	7	Canadian Grand Prix	2016-06-12	18:00:00	https://en.wikipedia.org/wiki/2016_Canadian_Grand_Prix
955	2016	8	73	European Grand Prix	2016-06-19	13:00:00	https://en.wikipedia.org/wiki/2016_European_Grand_Prix
956	2016	9	70	Austrian Grand Prix	2016-07-03	12:00:00	https://en.wikipedia.org/wiki/2016_Austrian_Grand_Prix
957	2016	10	9	British Grand Prix	2016-07-10	12:00:00	https://en.wikipedia.org/wiki/2016_British_Grand_Prix
958	2016	11	11	Hungarian Grand Prix	2016-07-24	12:00:00	https://en.wikipedia.org/wiki/2016_Hungarian_Grand_Prix
959	2016	12	10	German Grand Prix	2016-07-31	12:00:00	https://en.wikipedia.org/wiki/2016_German_Grand_Prix
960	2016	13	13	Belgian Grand Prix	2016-08-28	12:00:00	https://en.wikipedia.org/wiki/2016_Belgian_Grand_Prix
961	2016	14	14	Italian Grand Prix	2016-09-04	12:00:00	https://en.wikipedia.org/wiki/2016_Italian_Grand_Prix
962	2016	15	15	Singapore Grand Prix	2016-09-18	12:00:00	https://en.wikipedia.org/wiki/2016_Singapore_Grand_Prix
963	2016	16	2	Malaysian Grand Prix	2016-10-02	07:00:00	https://en.wikipedia.org/wiki/2016_Malaysian_Grand_Prix
964	2016	17	22	Japanese Grand Prix	2016-10-09	05:00:00	https://en.wikipedia.org/wiki/2016_Japanese_Grand_Prix
965	2016	18	69	United States Grand Prix	2016-10-23	19:00:00	https://en.wikipedia.org/wiki/2016_United_States_Grand_Prix
966	2016	19	32	Mexican Grand Prix	2016-10-30	19:00:00	https://en.wikipedia.org/wiki/2016_Mexican_Grand_Prix
967	2016	20	18	Brazilian Grand Prix	2016-11-13	16:00:00	https://en.wikipedia.org/wiki/2016_Brazilian_Grand_Prix
968	2016	21	24	Abu Dhabi Grand Prix	2016-11-27	13:00:00	https://en.wikipedia.org/wiki/2016_Abu_Dhabi_Grand_Prix
969	2017	1	1	Australian Grand Prix	2017-03-26	05:00:00	https://en.wikipedia.org/wiki/2017_Australian_Grand_Prix
970	2017	2	17	Chinese Grand Prix	2017-04-09	06:00:00	https://en.wikipedia.org/wiki/2017_Chinese_Grand_Prix
971	2017	3	3	Bahrain Grand Prix	2017-04-16	15:00:00	https://en.wikipedia.org/wiki/2017_Bahrain_Grand_Prix
972	2017	4	71	Russian Grand Prix	2017-04-30	12:00:00	https://en.wikipedia.org/wiki/2017_Russian_Grand_Prix
973	2017	5	4	Spanish Grand Prix	2017-05-14	12:00:00	https://en.wikipedia.org/wiki/2017_Spanish_Grand_Prix
974	2017	6	6	Monaco Grand Prix	2017-05-28	12:00:00	https://en.wikipedia.org/wiki/2017_Monaco_Grand_Prix
975	2017	7	7	Canadian Grand Prix	2017-06-11	18:00:00	https://en.wikipedia.org/wiki/2017_Canadian_Grand_Prix
976	2017	8	73	Azerbaijan Grand Prix	2017-06-25	13:00:00	https://en.wikipedia.org/wiki/2017_Azerbaijan_Grand_Prix
977	2017	9	70	Austrian Grand Prix	2017-07-09	12:00:00	https://en.wikipedia.org/wiki/2017_Austrian_Grand_Prix
978	2017	10	9	British Grand Prix	2017-07-16	12:00:00	https://en.wikipedia.org/wiki/2017_British_Grand_Prix
979	2017	11	11	Hungarian Grand Prix	2017-07-30	12:00:00	https://en.wikipedia.org/wiki/2017_Hungarian_Grand_Prix
980	2017	12	13	Belgian Grand Prix	2017-08-27	12:00:00	https://en.wikipedia.org/wiki/2017_Belgian_Grand_Prix
981	2017	13	14	Italian Grand Prix	2017-09-03	12:00:00	https://en.wikipedia.org/wiki/2017_Italian_Grand_Prix
982	2017	14	15	Singapore Grand Prix	2017-09-17	12:00:00	https://en.wikipedia.org/wiki/2017_Singapore_Grand_Prix
983	2017	15	2	Malaysian Grand Prix	2017-10-01	07:00:00	https://en.wikipedia.org/wiki/2017_Malaysian_Grand_Prix
984	2017	16	22	Japanese Grand Prix	2017-10-08	05:00:00	https://en.wikipedia.org/wiki/2017_Japanese_Grand_Prix
985	2017	17	69	United States Grand Prix	2017-10-22	19:00:00	https://en.wikipedia.org/wiki/2017_United_States_Grand_Prix
986	2017	18	32	Mexican Grand Prix	2017-10-29	19:00:00	https://en.wikipedia.org/wiki/2017_Mexican_Grand_Prix
987	2017	19	18	Brazilian Grand Prix	2017-11-12	16:00:00	https://en.wikipedia.org/wiki/2017_Brazilian_Grand_Prix
988	2017	20	24	Abu Dhabi Grand Prix	2017-11-26	13:00:00	https://en.wikipedia.org/wiki/2017_Abu_Dhabi_Grand_Prix
989	2018	1	1	Australian Grand Prix	2018-03-25	05:10:00	https://en.wikipedia.org/wiki/2018_Australian_Grand_Prix
990	2018	2	3	Bahrain Grand Prix	2018-04-08	15:10:00	https://en.wikipedia.org/wiki/2018_Bahrain_Grand_Prix
991	2018	3	17	Chinese Grand Prix	2018-04-15	06:10:00	https://en.wikipedia.org/wiki/2018_Chinese_Grand_Prix
992	2018	4	73	Azerbaijan Grand Prix	2018-04-29	12:10:00	https://en.wikipedia.org/wiki/2018_Azerbaijan_Grand_Prix
993	2018	5	4	Spanish Grand Prix	2018-05-13	13:10:00	https://en.wikipedia.org/wiki/2018_Spanish_Grand_Prix
994	2018	6	6	Monaco Grand Prix	2018-05-27	13:10:00	https://en.wikipedia.org/wiki/2018_Monaco_Grand_Prix
995	2018	7	7	Canadian Grand Prix	2018-06-10	18:10:00	https://en.wikipedia.org/wiki/2018_Canadian_Grand_Prix
996	2018	8	34	French Grand Prix	2018-06-24	14:10:00	https://en.wikipedia.org/wiki/2018_French_Grand_Prix
997	2018	9	70	Austrian Grand Prix	2018-07-01	13:10:00	https://en.wikipedia.org/wiki/2018_Austrian_Grand_Prix
998	2018	10	9	British Grand Prix	2018-07-08	13:10:00	https://en.wikipedia.org/wiki/2018_British_Grand_Prix
999	2018	11	10	German Grand Prix	2018-07-22	13:10:00	https://en.wikipedia.org/wiki/2018_German_Grand_Prix
1000	2018	12	11	Hungarian Grand Prix	2018-07-29	13:10:00	https://en.wikipedia.org/wiki/2018_Hungarian_Grand_Prix
1001	2018	13	13	Belgian Grand Prix	2018-08-26	13:10:00	https://en.wikipedia.org/wiki/2018_Belgian_Grand_Prix
1002	2018	14	14	Italian Grand Prix	2018-09-02	13:10:00	https://en.wikipedia.org/wiki/2018_Italian_Grand_Prix
1003	2018	15	15	Singapore Grand Prix	2018-09-16	12:10:00	https://en.wikipedia.org/wiki/2018_Singapore_Grand_Prix
1004	2018	16	71	Russian Grand Prix	2018-09-30	11:10:00	https://en.wikipedia.org/wiki/2018_Russian_Grand_Prix
1005	2018	17	22	Japanese Grand Prix	2018-10-07	05:10:00	https://en.wikipedia.org/wiki/2018_Japanese_Grand_Prix
1006	2018	18	69	United States Grand Prix	2018-10-21	18:10:00	https://en.wikipedia.org/wiki/2018_United_States_Grand_Prix
1007	2018	19	32	Mexican Grand Prix	2018-10-28	19:10:00	https://en.wikipedia.org/wiki/2018_Mexican_Grand_Prix
1008	2018	20	18	Brazilian Grand Prix	2018-11-11	17:10:00	https://en.wikipedia.org/wiki/2018_Brazilian_Grand_Prix
1009	2018	21	24	Abu Dhabi Grand Prix	2018-11-25	13:10:00	https://en.wikipedia.org/wiki/2018_Abu_Dhabi_Grand_Prix
1010	2019	1	1	Australian Grand Prix	2019-03-17	05:10:00	https://en.wikipedia.org/wiki/2019_Australian_Grand_Prix
1011	2019	2	3	Bahrain Grand Prix	2019-03-31	15:10:00	https://en.wikipedia.org/wiki/2019_Bahrain_Grand_Prix
1012	2019	3	17	Chinese Grand Prix	2019-04-14	06:10:00	https://en.wikipedia.org/wiki/2019_Chinese_Grand_Prix
1013	2019	4	73	Azerbaijan Grand Prix	2019-04-28	12:10:00	https://en.wikipedia.org/wiki/2019_Azerbaijan_Grand_Prix
1014	2019	5	4	Spanish Grand Prix	2019-05-12	13:10:00	https://en.wikipedia.org/wiki/2019_Spanish_Grand_Prix
1015	2019	6	6	Monaco Grand Prix	2019-05-26	13:10:00	https://en.wikipedia.org/wiki/2019_Monaco_Grand_Prix
1016	2019	7	7	Canadian Grand Prix	2019-06-09	18:10:00	https://en.wikipedia.org/wiki/2019_Canadian_Grand_Prix
1017	2019	8	34	French Grand Prix	2019-06-23	13:10:00	https://en.wikipedia.org/wiki/2019_French_Grand_Prix
1018	2019	9	70	Austrian Grand Prix	2019-06-30	13:10:00	https://en.wikipedia.org/wiki/2019_Austrian_Grand_Prix
1019	2019	10	9	British Grand Prix	2019-07-14	13:10:00	https://en.wikipedia.org/wiki/2019_British_Grand_Prix
1020	2019	11	10	German Grand Prix	2019-07-28	13:10:00	https://en.wikipedia.org/wiki/2019_German_Grand_Prix
1021	2019	12	11	Hungarian Grand Prix	2019-08-04	13:10:00	https://en.wikipedia.org/wiki/2019_Hungarian_Grand_Prix
1022	2019	13	13	Belgian Grand Prix	2019-09-01	13:10:00	https://en.wikipedia.org/wiki/2019_Belgian_Grand_Prix
1023	2019	14	14	Italian Grand Prix	2019-09-08	13:10:00	https://en.wikipedia.org/wiki/2019_Italian_Grand_Prix
1024	2019	15	15	Singapore Grand Prix	2019-09-22	12:10:00	https://en.wikipedia.org/wiki/2019_Singapore_Grand_Prix
1025	2019	16	71	Russian Grand Prix	2019-09-29	11:10:00	https://en.wikipedia.org/wiki/2019_Russian_Grand_Prix
1026	2019	17	22	Japanese Grand Prix	2019-10-13	05:10:00	https://en.wikipedia.org/wiki/2019_Japanese_Grand_Prix
1027	2019	18	32	Mexican Grand Prix	2019-10-27	19:10:00	https://en.wikipedia.org/wiki/2019_Mexican_Grand_Prix
1028	2019	19	69	United States Grand Prix	2019-11-03	19:10:00	https://en.wikipedia.org/wiki/2019_United_States_Grand_Prix
1029	2019	20	18	Brazilian Grand Prix	2019-11-17	17:10:00	https://en.wikipedia.org/wiki/2019_Brazilian_Grand_Prix
1030	2019	21	24	Abu Dhabi Grand Prix	2019-12-01	13:10:00	https://en.wikipedia.org/wiki/2019_Abu_Dhabi_Grand_Prix
1041	2020	1	70	Austrian Grand Prix	2020-07-05	13:10:00	https://en.wikipedia.org/wiki/2020_Austrian_Grand_Prix
1042	2020	2	70	Styrian Grand Prix	2020-07-12	13:10:00	https://en.wikipedia.org/wiki/2020_Styrian_Grand_Prix
1043	2020	3	11	Hungarian Grand Prix	2020-07-19	13:10:00	https://en.wikipedia.org/wiki/2020_Hungarian_Grand_Prix
1044	2020	4	9	British Grand Prix	2020-08-02	13:10:00	https://en.wikipedia.org/wiki/2020_British_Grand_Prix
1045	2020	5	9	70th Anniversary Grand Prix	2020-08-09	13:10:00	https://en.wikipedia.org/wiki/70th_Anniversary_Grand_Prix
1046	2020	6	4	Spanish Grand Prix	2020-08-16	13:10:00	https://en.wikipedia.org/wiki/2020_Spanish_Grand_Prix
1047	2020	7	13	Belgian Grand Prix	2020-08-30	13:10:00	https://en.wikipedia.org/wiki/2020_Belgian_Grand_Prix
1048	2020	8	14	Italian Grand Prix	2020-09-06	13:10:00	https://en.wikipedia.org/wiki/2020_Italian_Grand_Prix
\.


--
-- Data for Name: fact_session_race_results; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fact_session_race_results (result_id, race_id, driver_id, constructor_id, number, grid, "position", position_str, position_order, laps, "time", milliseconds, fastest_lap, rank, fastest_lap_time, status_id) FROM stdin;
23334	966	836	209	94	16	\N	R	22	0	\N	\N	\N	0	\N	4
20779	841	20	9	1	1	1	1	1	58	1:29:30.259	5370259	44	4	00:01:29.844	1
20780	841	1	1	3	2	2	2	2	58	+22.297	5392556	41	8	00:01:30.314	1
20781	841	808	4	10	6	3	3	3	58	+30.560	5400819	55	7	00:01:30.064	1
20782	841	4	6	5	5	4	4	4	58	+31.772	5402031	49	2	00:01:29.487	1
20783	841	17	9	2	3	5	5	5	58	+38.171	5408430	50	3	00:01:29.6	1
20784	841	18	1	4	4	6	6	6	58	+54.304	5424563	49	5	00:01:29.883	1
20785	841	13	6	6	8	7	7	7	58	+1:25.186	5455445	55	1	00:01:28.947	1
20786	841	67	5	18	10	8	8	8	57	\N	\N	44	11	00:01:30.836	11
20787	841	16	10	14	16	9	9	9	57	\N	\N	55	13	00:01:31.526	11
20788	841	814	10	15	14	10	10	10	57	\N	\N	40	14	00:01:31.941	11
20789	841	153	5	19	12	11	11	11	57	\N	\N	41	10	00:01:30.467	11
20790	841	2	4	9	18	12	12	12	57	\N	\N	43	15	00:01:32.377	11
20791	841	15	205	21	20	13	13	13	56	\N	\N	52	16	00:01:32.55	12
20792	841	816	166	25	22	14	14	14	54	\N	\N	44	19	00:01:34.523	14
20793	841	10	166	24	21	\N	N	15	49	\N	\N	48	22	00:01:35.789	19
20794	841	22	3	11	17	\N	R	16	48	\N	\N	47	12	00:01:31.404	7
20795	841	3	131	8	7	\N	R	17	22	\N	\N	21	17	00:01:33.503	4
20796	841	5	205	20	19	\N	R	18	19	\N	\N	19	20	00:01:34.918	47
20797	841	30	131	7	11	\N	R	19	19	\N	\N	13	21	00:01:35.319	4
20798	841	813	3	12	15	\N	R	20	9	\N	\N	7	18	00:01:34.102	7
20799	841	155	15	16	9	\N	D	21	58	\N	\N	51	9	00:01:30.384	2
20800	841	815	15	17	13	\N	D	22	58	\N	\N	39	6	00:01:29.962	2
20801	842	20	9	1	1	1	1	1	56	1:37:39.832	5859832	33	6	00:01:41.539	1
20802	842	18	1	4	4	2	2	2	56	+3.261	5863093	50	4	00:01:41.264	1
20803	842	2	4	9	6	3	3	3	56	+25.075	5884907	47	7	00:01:41.547	1
20804	842	17	9	2	3	4	4	4	56	+26.384	5886216	46	1	00:01:40.571	1
20805	842	13	6	6	7	5	5	5	56	+36.958	5896790	41	9	00:01:41.999	1
20806	842	4	6	5	5	6	6	6	56	+37.248	5897080	49	2	00:01:40.717	1
20807	842	155	15	16	10	7	7	7	56	+1:06.439	5926271	39	10	00:01:42.095	1
20808	842	1	1	3	2	8	8	8	56	+1:09.957	5929789	54	5	00:01:41.512	1
20809	842	30	131	7	11	9	9	9	56	+1:24.896	5944728	45	11	00:01:42.491	1
20810	842	814	10	15	14	10	10	10	56	+1:31.563	5951395	48	13	00:01:42.883	1
20811	842	16	10	14	17	11	11	11	55	+1:41.379	5961211	34	14	00:01:42.973	11
20812	842	3	131	8	9	12	12	12	55	\N	\N	45	8	00:01:41.778	11
20813	842	67	5	18	12	13	13	13	55	\N	\N	36	12	00:01:42.659	11
20814	842	153	5	19	13	14	14	14	55	\N	\N	37	17	00:01:43.744	11
20815	842	5	205	20	19	15	15	15	55	\N	\N	43	16	00:01:43.677	11
20816	842	10	166	24	21	16	16	16	54	\N	\N	50	20	00:01:45.357	12
20817	842	808	4	10	8	17	17	17	52	\N	\N	49	3	00:01:41.054	3
20818	842	24	164	23	23	\N	R	18	46	\N	\N	42	23	00:01:46.521	88
20819	842	816	166	25	22	\N	R	19	42	\N	\N	41	19	00:01:45.346	3
20820	842	15	205	21	20	\N	R	20	31	\N	\N	23	18	00:01:45.28	8
20821	842	815	15	17	16	\N	R	21	23	\N	\N	19	15	00:01:43.298	3
20822	842	22	3	11	15	\N	R	22	22	\N	\N	10	21	00:01:45.516	6
20823	842	39	164	22	24	\N	R	23	14	\N	\N	5	24	00:01:49.385	128
20824	842	813	3	12	18	\N	R	24	8	\N	\N	5	22	00:01:45.689	129
20825	843	1	1	3	3	1	1	1	56	1:36:58.226	5818226	48	2	00:01:40.415	1
20826	843	20	9	1	1	2	2	2	56	+5.198	5823424	47	8	00:01:41.321	1
20827	843	17	9	2	18	3	3	3	56	+7.555	5825781	42	1	00:01:38.993	1
20828	843	18	1	4	2	4	4	4	56	+10.000	5828226	39	3	00:01:40.623	1
20829	843	3	131	8	4	5	5	5	56	+13.448	5831674	41	5	00:01:41.166	1
20830	843	13	6	6	6	6	6	6	56	+15.840	5834066	39	10	00:01:41.678	1
20831	843	4	6	5	5	7	7	7	56	+30.622	5848848	41	15	00:01:42.07	1
20832	843	30	131	7	14	8	8	8	56	+31.026	5849252	46	6	00:01:41.215	1
20833	843	808	4	10	10	9	9	9	56	+57.404	5875630	50	7	00:01:41.261	1
20834	843	155	15	16	13	10	10	10	56	+1:03.273	5881499	32	17	00:01:42.577	1
20835	843	814	10	15	8	11	11	11	56	+1:08.757	5886983	45	18	00:01:42.614	1
20836	843	2	4	9	16	12	12	12	56	+1:12.739	5890965	51	16	00:01:42.406	1
20837	843	22	3	11	15	13	13	13	56	+1:30.189	5908415	45	13	00:01:42.031	1
20838	843	67	5	18	9	14	14	14	56	+1:30.671	5908897	45	11	00:01:41.696	1
20839	843	16	10	14	11	15	15	15	55	\N	\N	54	4	00:01:41.157	11
20840	843	5	205	20	19	16	16	16	55	\N	\N	45	19	00:01:42.672	11
20841	843	815	15	17	12	17	17	17	55	\N	\N	39	9	00:01:41.643	11
20842	843	813	3	12	17	18	18	18	55	\N	\N	46	12	00:01:41.702	11
20843	843	15	205	21	20	19	19	19	55	\N	\N	53	14	00:01:42.052	11
20844	843	816	166	25	21	20	20	20	54	\N	\N	45	22	00:01:44.806	12
20845	843	10	166	24	22	21	21	21	54	\N	\N	54	21	00:01:44.381	12
20846	843	24	164	23	23	22	22	22	54	\N	\N	52	20	00:01:43.384	12
20847	843	39	164	22	24	23	23	23	54	\N	\N	41	24	00:01:46.081	12
20848	843	153	5	19	7	\N	R	24	9	\N	\N	5	23	00:01:45.7	36
20849	844	20	9	1	1	1	1	1	58	1:30:17.558	5417558	50	3	00:01:29.937	1
20850	844	17	9	2	2	2	2	2	58	+8.807	5426365	48	1	00:01:29.703	1
20851	844	4	6	5	5	3	3	3	58	+10.075	5427633	48	6	00:01:30.279	1
20852	844	1	1	3	4	4	4	4	58	+40.232	5457790	48	4	00:01:30.108	1
20853	844	3	131	8	3	5	5	5	58	+47.539	5465097	47	7	00:01:30.573	1
20854	844	18	1	4	6	6	6	6	58	+59.431	5476989	47	13	00:01:31.167	1
20855	844	2	4	9	9	7	7	7	58	+1:00.857	5478415	52	5	00:01:30.158	1
20856	844	808	4	10	7	8	8	8	58	+1:08.168	5485726	48	8	00:01:30.618	1
20857	844	67	5	18	16	9	9	9	58	+1:09.394	5486952	44	14	00:01:31.36	1
20858	844	155	15	16	24	10	10	10	58	+1:18.021	5495579	45	10	00:01:31.038	1
20859	844	13	6	6	10	11	11	11	58	+1:19.823	5497381	57	11	00:01:31.118	1
20860	844	30	131	7	8	12	12	12	58	+1:25.444	5503002	47	12	00:01:31.153	1
20861	844	16	10	14	12	13	13	13	57	\N	\N	43	16	00:01:32.07	11
20862	844	815	15	17	15	14	14	14	57	\N	\N	46	9	00:01:30.797	11
20863	844	22	3	11	11	15	15	15	57	\N	\N	46	17	00:01:32.079	11
20864	844	153	5	19	17	16	16	16	57	\N	\N	57	2	00:01:29.894	11
20865	844	813	3	12	14	17	17	17	57	\N	\N	44	15	00:01:32.044	11
20866	844	15	205	21	19	18	18	18	57	\N	\N	49	20	00:01:32.862	11
20867	844	5	205	20	18	19	19	19	56	\N	\N	55	19	00:01:32.695	12
20868	844	816	166	25	23	20	20	20	56	\N	\N	55	23	00:01:34.971	12
20869	844	39	164	22	22	21	21	21	55	\N	\N	51	21	00:01:33.948	13
20870	844	24	164	23	20	22	22	22	53	\N	\N	41	22	00:01:34.699	15
20871	844	814	10	15	13	\N	R	23	44	\N	\N	40	18	00:01:32.519	31
20872	844	10	166	24	21	\N	W	24	0	\N	\N	\N	0	\N	6
20873	845	20	9	1	2	1	1	1	66	1:39:03.301	5943301	60	4	00:01:27.162	1
20874	845	1	1	3	3	2	2	2	66	+0.630	5943931	52	1	00:01:26.727	1
20875	845	18	1	4	5	3	3	3	66	+35.697	5978998	63	7	00:01:27.518	1
20876	845	17	9	2	1	4	4	4	66	+47.966	5991267	50	5	00:01:27.187	1
20877	845	4	6	5	4	5	5	5	65	\N	\N	22	9	00:01:28.737	11
20878	845	30	131	7	10	6	6	6	65	\N	\N	34	15	00:01:29.463	11
20879	845	3	131	8	7	7	7	7	65	\N	\N	34	13	00:01:29.155	11
20880	845	2	4	9	24	8	8	8	65	\N	\N	61	3	00:01:26.958	11
20881	845	815	15	17	12	9	9	9	65	\N	\N	55	6	00:01:27.247	11
20882	845	155	15	16	14	10	10	10	65	\N	\N	52	8	00:01:27.615	11
20883	845	808	4	10	6	11	11	11	65	\N	\N	35	17	00:01:29.592	11
20884	845	814	10	15	16	12	12	12	65	\N	\N	42	16	00:01:29.469	11
20885	845	16	10	14	17	13	13	13	65	\N	\N	52	10	00:01:28.791	11
20886	845	67	5	18	11	14	14	14	65	\N	\N	27	18	00:01:30.049	11
20887	845	813	3	12	9	15	15	15	65	\N	\N	64	14	00:01:29.391	11
20888	845	153	5	19	13	16	16	16	64	\N	\N	52	12	00:01:29.132	12
20889	845	22	3	11	19	17	17	17	64	\N	\N	60	2	00:01:26.891	12
20890	845	15	205	21	18	18	18	18	64	\N	\N	34	20	00:01:30.783	12
20891	845	10	166	24	20	19	19	19	63	\N	\N	40	21	00:01:31.635	13
20892	845	816	166	25	23	20	20	20	62	\N	\N	36	22	00:01:32.549	14
20893	845	39	164	22	22	21	21	21	61	\N	\N	33	23	00:01:32.848	15
20894	845	13	6	6	8	\N	R	22	58	\N	\N	24	11	00:01:29.081	6
20895	845	5	205	20	15	\N	R	23	48	\N	\N	34	19	00:01:30.618	3
20896	845	24	164	23	21	\N	R	24	28	\N	\N	22	24	00:01:33.884	6
20897	846	20	9	1	1	1	1	1	78	2:09:38.373	7778373	78	2	00:01:16.267	1
20898	846	4	6	5	4	2	2	2	78	+1.138	7779511	77	4	00:01:16.471	1
20899	846	18	1	4	2	3	3	3	78	+2.378	7780751	78	3	00:01:16.463	1
20900	846	17	9	2	3	4	4	4	78	+23.101	7801474	78	1	00:01:16.234	1
20901	846	155	15	16	12	5	5	5	78	+26.916	7805289	76	7	00:01:18.308	1
20902	846	1	1	3	9	6	6	6	78	+27.210	7805583	54	5	00:01:17.847	1
20903	846	16	10	14	14	7	7	7	77	\N	\N	77	13	00:01:18.872	11
20904	846	2	4	9	15	8	8	8	77	\N	\N	77	6	00:01:17.857	11
20905	846	22	3	11	11	9	9	9	77	\N	\N	76	8	00:01:18.584	11
20906	846	67	5	18	16	10	10	10	77	\N	\N	77	12	00:01:18.832	11
20907	846	3	131	8	7	11	11	11	76	\N	\N	56	10	00:01:18.699	12
20908	846	814	10	15	13	12	12	12	76	\N	\N	75	11	00:01:18.724	12
20909	846	15	205	21	18	13	13	13	76	\N	\N	66	19	00:01:21.277	12
20910	846	5	205	20	17	14	14	14	76	\N	\N	54	18	00:01:20.678	12
20911	846	816	166	25	21	15	15	15	75	\N	\N	75	20	00:01:21.391	13
20912	846	24	164	23	23	16	16	16	75	\N	\N	74	21	00:01:21.566	13
20913	846	39	164	22	22	17	17	17	74	\N	\N	74	23	00:01:22.731	14
20914	846	813	3	12	8	18	18	18	73	\N	\N	62	14	00:01:18.904	3
20915	846	808	4	10	10	\N	R	19	67	\N	\N	57	16	00:01:20.058	4
20916	846	153	5	19	19	\N	R	20	66	\N	\N	59	9	00:01:18.608	4
20917	846	13	6	6	6	\N	R	21	32	\N	\N	16	17	00:01:20.202	3
20918	846	30	131	7	5	\N	R	22	32	\N	\N	30	15	00:01:19.801	5
20919	846	10	166	24	20	\N	R	23	30	\N	\N	30	22	00:01:22.102	22
20920	847	18	1	4	7	1	1	1	70	4:04:39.537	14679537	69	1	00:01:16.956	1
20921	847	20	9	1	1	2	2	2	70	+2.709	14682246	69	2	00:01:17.217	1
20922	847	17	9	2	4	3	3	3	70	+13.828	14693365	65	8	00:01:19.572	1
20923	847	30	131	7	8	4	4	4	70	+14.219	14693756	70	4	00:01:19.138	1
20924	847	808	4	10	10	5	5	5	70	+20.395	14699932	68	3	00:01:19.054	1
20925	847	13	6	6	3	6	6	6	70	+33.225	14712762	68	5	00:01:19.148	1
20926	847	155	15	16	13	7	7	7	70	+33.270	14712807	70	10	00:01:20.213	1
20927	847	153	5	19	24	8	8	8	70	+35.964	14715501	69	13	00:01:20.371	1
20928	847	22	3	11	16	9	9	9	70	+45.117	14724654	68	11	00:01:20.316	1
20929	847	67	5	18	15	10	10	10	70	+47.056	14726593	69	7	00:01:19.507	1
20930	847	3	131	8	6	11	11	11	70	+50.454	14729991	69	9	00:01:20.071	1
20931	847	37	15	17	17	12	12	12	70	+1:03.607	14743144	70	12	00:01:20.369	1
20932	847	24	164	23	20	13	13	13	69	\N	\N	63	17	00:01:23.419	11
20933	847	39	164	22	22	14	14	14	69	\N	\N	66	16	00:01:23.116	11
20934	847	816	166	25	23	15	15	15	69	\N	\N	68	15	00:01:22.495	11
20935	847	10	166	24	21	16	16	16	69	\N	\N	68	19	00:01:24.59	11
20936	847	15	205	21	18	17	17	17	69	\N	\N	67	14	00:01:22.233	11
20937	847	814	10	15	11	18	18	18	67	\N	\N	67	6	00:01:19.395	3
20938	847	813	3	12	12	\N	R	19	61	\N	\N	53	18	00:01:24.265	31
20939	847	2	4	9	9	\N	R	20	55	\N	\N	55	20	00:01:25.135	3
20940	847	16	10	14	14	\N	R	21	49	\N	\N	47	21	00:01:30.171	3
20941	847	4	6	5	2	\N	R	22	36	\N	\N	14	22	00:01:34.223	4
20942	847	5	205	20	19	\N	R	23	28	\N	\N	16	24	00:01:38.46	7
20943	847	1	1	3	5	\N	R	24	7	\N	\N	7	23	00:01:37.761	4
20944	848	20	9	1	1	1	1	1	57	1:39:36.169	5976169	53	1	00:01:41.852	1
20945	848	4	6	5	4	2	2	2	57	+10.891	5987060	49	2	00:01:42.308	1
20946	848	17	9	2	2	3	3	3	57	+27.255	6003424	39	4	00:01:42.534	1
20947	848	1	1	3	3	4	4	4	57	+46.190	6022359	47	6	00:01:42.947	1
20948	848	13	6	6	5	5	5	5	57	+51.705	6027874	53	5	00:01:42.705	1
20949	848	18	1	4	6	6	6	6	57	+1:00.065	6036234	57	3	00:01:42.34	1
20950	848	3	131	8	7	7	7	7	57	+1:38.090	6074259	53	12	00:01:43.649	1
20951	848	153	5	19	18	8	8	8	56	\N	\N	53	11	00:01:43.579	11
20952	848	16	10	14	10	9	9	9	56	\N	\N	53	10	00:01:43.526	11
20953	848	2	4	9	9	10	10	10	56	\N	\N	51	14	00:01:43.901	11
20954	848	815	15	17	16	11	11	11	56	\N	\N	41	15	00:01:43.949	11
20955	848	22	3	11	13	12	12	12	56	\N	\N	55	17	00:01:44.131	11
20956	848	67	5	18	17	13	13	13	56	\N	\N	47	16	00:01:44.103	11
20957	848	814	10	15	12	14	14	14	56	\N	\N	54	13	00:01:43.851	11
20958	848	808	4	10	11	15	15	15	56	\N	\N	41	8	00:01:43.151	11
20959	848	155	15	16	14	16	16	16	56	\N	\N	42	9	00:01:43.517	11
20960	848	30	131	7	8	17	17	17	56	\N	\N	50	18	00:01:44.578	11
20961	848	813	3	12	15	18	18	18	56	\N	\N	47	7	00:01:43.134	11
23518	975	832	5	55	13	\N	R	20	0	\N	\N	\N	0	\N	4
20962	848	5	205	20	19	19	19	19	55	\N	\N	44	19	00:01:45.055	12
20963	848	15	205	21	20	20	20	20	55	\N	\N	28	20	00:01:46.208	12
20964	848	10	166	24	21	21	21	21	55	\N	\N	49	21	00:01:46.628	12
20965	848	816	166	25	23	22	22	22	55	\N	\N	51	22	00:01:47.164	12
20966	848	24	164	23	22	23	23	23	54	\N	\N	37	23	00:01:47.418	13
20967	848	39	164	22	24	24	24	24	54	\N	\N	32	24	00:01:47.708	13
20968	849	4	6	5	3	1	1	1	52	1:28:41.196	5321196	41	1	00:01:34.908	1
20969	849	20	9	1	2	2	2	2	52	+16.511	5337707	38	3	00:01:35.565	1
20970	849	17	9	2	1	3	3	3	52	+16.947	5338143	49	4	00:01:35.665	1
20971	849	1	1	3	10	4	4	4	52	+28.986	5350182	39	5	00:01:36.18	1
20972	849	13	6	6	4	5	5	5	52	+29.010	5350206	49	2	00:01:35.474	1
20973	849	3	131	8	9	6	6	6	52	+1:00.665	5381861	32	13	00:01:37.073	1
20974	849	815	15	17	12	7	7	7	52	+1:05.590	5386786	35	7	00:01:36.656	1
20975	849	2	4	9	16	8	8	8	52	+1:15.542	5396738	37	14	00:01:37.117	1
20976	849	30	131	7	13	9	9	9	52	+1:17.912	5399108	34	11	00:01:37.034	1
20977	849	153	5	19	18	10	10	10	52	+1:19.108	5400304	38	15	00:01:37.16	1
20978	849	16	10	14	11	11	11	11	52	+1:19.712	5400908	42	9	00:01:36.744	1
20979	849	808	4	10	14	12	12	12	52	+1:20.681	5401877	40	6	00:01:36.308	1
20980	849	22	3	11	15	13	13	13	51	\N	\N	38	8	00:01:36.733	11
20981	849	813	3	12	7	14	14	14	51	\N	\N	41	12	00:01:37.036	11
20982	849	814	10	15	6	15	15	15	51	\N	\N	48	16	00:01:37.936	11
20983	849	10	166	24	20	16	16	16	50	\N	\N	49	17	00:01:39.811	12
20984	849	816	166	25	22	17	17	17	50	\N	\N	30	20	00:01:40.56	12
20985	849	24	164	23	23	18	18	18	50	\N	\N	40	19	00:01:40.524	12
20986	849	817	164	22	24	19	19	19	49	\N	\N	30	22	00:01:40.91	13
20987	849	18	1	4	5	\N	R	20	39	\N	\N	31	10	00:01:36.982	61
20988	849	67	5	18	19	\N	R	21	25	\N	\N	24	18	00:01:40.224	3
20989	849	155	15	16	8	\N	R	22	23	\N	\N	23	21	00:01:40.703	5
20990	849	15	205	21	21	\N	R	23	10	\N	\N	9	23	00:01:55.491	44
20991	849	5	205	20	17	\N	R	24	2	\N	\N	2	24	00:02:10.404	6
20992	850	1	1	3	2	1	1	1	60	1:37:30.344	5850334	59	1	00:01:34.302	1
20993	850	4	6	5	4	2	2	2	60	+3.980	5854314	60	5	00:01:34.626	1
20994	850	17	9	2	1	3	3	3	60	+9.788	5860122	60	2	00:01:34.468	1
20995	850	20	9	1	3	4	4	4	60	+47.921	5898255	47	3	00:01:34.587	1
20996	850	13	6	6	5	5	5	5	60	+52.252	5902586	51	4	00:01:34.609	1
20997	850	16	10	14	8	6	6	6	60	+1:26.208	5936542	57	10	00:01:36.653	1
20998	850	3	131	8	6	7	7	7	59	\N	\N	51	7	00:01:36.181	11
20999	850	30	131	7	10	8	8	8	59	\N	\N	49	6	00:01:35.628	11
21000	850	155	15	16	17	9	9	9	59	\N	\N	50	11	00:01:36.659	11
21001	850	808	4	10	9	10	10	10	59	\N	\N	50	8	00:01:36.186	11
21002	850	815	15	17	15	11	11	11	59	\N	\N	53	13	00:01:37.033	11
21003	850	153	5	19	16	12	12	12	59	\N	\N	59	14	00:01:37.415	11
21004	850	814	10	15	12	13	13	13	59	\N	\N	54	12	00:01:36.715	11
21005	850	813	3	12	13	14	14	14	59	\N	\N	50	15	00:01:37.568	11
21006	850	67	5	18	24	15	15	15	59	\N	\N	48	16	00:01:37.863	11
21007	850	5	205	20	18	16	16	16	58	\N	\N	54	17	00:01:39.05	12
21008	850	10	166	24	19	17	17	17	57	\N	\N	57	21	00:01:39.982	13
21009	850	816	166	25	21	18	18	18	57	\N	\N	57	20	00:01:39.787	13
21010	850	817	164	22	22	19	19	19	57	\N	\N	57	23	00:01:40.489	13
21011	850	812	205	21	20	20	20	20	56	\N	\N	56	22	00:01:40.435	14
21012	850	24	164	23	23	\N	R	21	37	\N	\N	28	24	00:01:40.683	10
21013	850	18	1	4	7	\N	R	22	35	\N	\N	33	9	00:01:36.258	9
21014	850	22	3	11	14	\N	R	23	16	\N	\N	8	19	00:01:39.679	44
21015	850	2	4	9	11	\N	R	24	9	\N	\N	7	18	00:01:39.452	4
21016	851	18	1	4	3	1	1	1	70	1:46:42.337	6402337	58	6	00:01:23.937	1
21017	851	20	9	1	1	2	2	2	70	+3.588	6405925	70	5	00:01:23.875	1
21018	851	4	6	5	5	3	3	3	70	+19.819	6422156	62	3	00:01:23.711	1
21019	851	1	1	3	2	4	4	4	70	+48.338	6450675	61	2	00:01:23.661	1
21020	851	17	9	2	6	5	5	5	70	+49.742	6452079	61	4	00:01:23.718	1
21021	851	13	6	6	4	6	6	6	70	+1:23.176	6485513	61	1	00:01:23.415	1
21022	851	814	10	15	11	7	7	7	69	\N	\N	65	14	00:01:25.935	11
21023	851	67	5	18	23	8	8	8	69	\N	\N	65	15	00:01:25.977	11
21024	851	3	131	8	7	9	9	9	69	\N	\N	64	9	00:01:24.857	11
21025	851	153	5	19	16	10	10	10	69	\N	\N	68	16	00:01:26.025	11
21026	851	155	15	16	13	11	11	11	69	\N	\N	65	7	00:01:24.664	11
21027	851	808	4	10	12	12	12	12	69	\N	\N	68	8	00:01:24.664	11
21028	851	22	3	11	15	13	13	13	68	\N	\N	65	11	00:01:25.018	12
21029	851	16	10	14	8	14	14	14	68	\N	\N	66	12	00:01:25.579	12
21030	851	815	15	17	10	15	15	15	68	\N	\N	67	10	00:01:24.999	12
21031	851	813	3	12	17	16	16	16	68	\N	\N	56	13	00:01:25.724	12
21032	851	10	166	24	20	17	17	17	66	\N	\N	59	18	00:01:28.022	14
21033	851	817	164	22	22	18	18	18	66	\N	\N	62	19	00:01:28.876	14
21034	851	816	166	25	24	19	19	19	65	\N	\N	58	20	00:01:29.068	15
21035	851	24	164	23	21	20	20	20	65	\N	\N	53	21	00:01:29.208	15
21036	851	5	205	20	18	\N	R	21	55	\N	\N	54	17	00:01:27.149	47
21037	851	30	131	7	9	\N	R	22	26	\N	\N	19	22	00:01:29.781	6
21038	851	2	4	9	14	\N	R	23	23	\N	\N	19	23	00:01:30.826	42
21039	851	15	205	21	19	\N	R	24	17	\N	\N	16	24	00:01:35.252	44
21040	852	20	9	1	1	1	1	1	44	1:26:44.893	5204893	36	4	00:01:50.451	1
21041	852	17	9	2	3	2	2	2	44	+3.741	5208634	33	1	00:01:49.883	1
21042	852	18	1	4	13	3	3	3	44	+9.669	5214562	39	2	00:01:50.062	1
21043	852	4	6	5	8	4	4	4	44	+13.022	5217915	41	5	00:01:51.107	1
21044	852	30	131	7	24	5	5	5	44	+47.464	5252357	34	6	00:01:51.137	1
21045	852	3	131	8	5	6	6	6	44	+48.674	5253567	39	8	00:01:52.263	1
21046	852	16	10	14	15	7	7	7	44	+59.713	5264606	33	10	00:01:52.591	1
21047	852	13	6	6	4	8	8	8	44	+1:06.076	5270969	42	7	00:01:51.564	1
21048	852	808	4	10	10	9	9	9	44	+1:11.917	5276810	34	9	00:01:52.432	1
21049	852	813	3	12	21	10	10	10	44	+1:17.615	5282508	43	12	00:01:53.362	1
21050	852	814	10	15	17	11	11	11	44	+1:23.994	5288887	32	11	00:01:53.223	1
21051	852	155	15	16	12	12	12	12	44	+1:31.976	5296869	35	14	00:01:53.871	1
21052	852	811	4	9	7	13	13	13	44	+1:32.985	5297878	39	13	00:01:53.585	1
21053	852	15	205	21	18	14	14	14	43	\N	\N	38	17	00:01:54.571	11
21054	852	5	205	20	16	15	15	15	43	\N	\N	35	15	00:01:54.051	11
21055	852	22	3	11	14	16	16	16	43	\N	\N	42	3	00:01:50.424	11
21056	852	816	166	25	20	17	17	17	43	\N	\N	38	19	00:01:56.319	11
21057	852	10	166	24	19	18	18	18	43	\N	\N	37	20	00:01:56.54	11
21058	852	24	164	23	22	19	19	19	43	\N	\N	42	22	00:01:58.061	11
21059	852	815	15	17	9	\N	R	20	27	\N	\N	26	16	00:01:54.244	22
21060	852	817	164	22	23	\N	R	21	13	\N	\N	10	23	00:01:59.831	5
21061	852	1	1	3	2	\N	R	22	12	\N	\N	8	18	00:01:55.647	4
21062	852	67	5	18	11	\N	R	23	6	\N	\N	4	21	00:01:56.79	65
21063	852	153	5	19	6	\N	R	24	0	\N	\N	\N	0	\N	4
21064	853	20	9	1	1	1	1	1	53	1:20:46.172	4846172	49	3	00:01:26.557	1
21065	853	18	1	4	3	2	2	2	53	+9.590	4855762	52	2	00:01:26.207	1
21066	853	4	6	5	4	3	3	3	53	+16.909	4863081	50	6	00:01:27.191	1
21067	853	1	1	3	2	4	4	4	53	+17.417	4863589	52	1	00:01:26.187	1
21068	853	30	131	7	8	5	5	5	53	+32.677	4878849	46	7	00:01:27.402	1
21069	853	13	6	6	6	6	6	6	53	+42.993	4889165	53	5	00:01:26.924	1
21070	853	153	5	19	18	7	7	7	52	\N	\N	49	10	00:01:28.357	11
21071	853	814	10	15	11	8	8	8	52	\N	\N	52	8	00:01:28.054	11
21072	853	811	4	9	10	9	9	9	52	\N	\N	51	4	00:01:26.895	11
21073	853	67	5	18	16	10	10	10	52	\N	\N	51	9	00:01:28.202	11
21074	853	813	3	12	14	11	11	11	52	\N	\N	51	12	00:01:28.934	11
21075	853	22	3	11	13	12	12	12	52	\N	\N	49	11	00:01:28.377	11
21076	853	5	205	20	20	13	13	13	51	\N	\N	50	14	00:01:29.639	12
21077	853	15	205	21	19	14	14	14	51	\N	\N	50	15	00:01:29.825	12
21078	853	10	166	24	21	15	15	15	51	\N	\N	51	17	00:01:30.783	12
21079	853	817	164	22	23	\N	N	16	39	\N	\N	36	20	00:01:32.013	111
21080	853	815	15	17	15	\N	R	17	32	\N	\N	29	13	00:01:29.403	6
21081	853	155	15	16	17	\N	R	18	21	\N	\N	21	16	00:01:30	6
21082	853	16	10	14	12	\N	R	19	9	\N	\N	8	19	00:01:31.455	9
21083	853	17	9	2	5	\N	R	20	4	\N	\N	4	18	00:01:30.994	3
21084	853	816	166	25	22	\N	R	21	1	\N	\N	\N	0	\N	6
21085	853	808	4	10	7	\N	R	22	0	\N	\N	\N	0	\N	4
21086	853	3	131	8	9	\N	R	23	0	\N	\N	\N	0	\N	4
21087	853	24	164	23	24	\N	R	24	0	\N	\N	\N	0	\N	4
21088	854	20	9	1	1	1	1	1	61	1:59:04.757	7146757	51	2	00:01:48.688	1
21089	854	18	1	4	3	2	2	2	61	+1.737	7148494	54	1	00:01:48.454	1
21090	854	17	9	2	2	3	3	3	61	+29.279	7176036	54	3	00:01:50.088	1
21091	854	4	6	5	5	4	4	4	61	+55.449	7202206	58	5	00:01:50.891	1
21092	854	1	1	3	4	5	5	5	61	+1:07.766	7214523	54	4	00:01:50.832	1
21093	854	814	10	15	10	6	6	6	61	+1:51.067	7257824	41	15	00:01:54.239	1
21094	854	3	131	8	7	7	7	7	60	\N	\N	42	16	00:01:54.383	11
21095	854	16	10	14	9	8	8	8	60	\N	\N	45	17	00:01:54.564	11
21096	854	13	6	6	6	9	9	9	60	\N	\N	26	8	00:01:52.55	11
21097	854	815	15	17	11	10	10	10	60	\N	\N	42	18	00:01:54.615	11
21098	854	813	3	12	13	11	11	11	60	\N	\N	50	10	00:01:53.198	11
21099	854	67	5	18	14	12	12	12	60	\N	\N	51	7	00:01:52.197	11
21100	854	22	3	11	12	13	13	13	60	\N	\N	40	19	00:01:55.235	11
21101	854	155	15	16	17	14	14	14	59	\N	\N	56	6	00:01:51.329	12
21102	854	811	4	9	15	15	15	15	59	\N	\N	55	12	00:01:53.774	12
21103	854	5	205	20	19	16	16	16	59	\N	\N	56	13	00:01:54.063	12
21104	854	808	4	10	18	17	17	17	59	\N	\N	56	14	00:01:54.204	12
21105	854	816	166	25	22	18	18	18	59	\N	\N	22	22	00:01:58.73	12
21106	854	817	164	22	23	19	19	19	57	\N	\N	40	23	00:01:59.064	14
21107	854	24	164	23	24	20	20	20	57	\N	\N	41	21	00:01:58.283	14
21108	854	153	5	19	16	21	21	21	56	\N	\N	37	11	00:01:53.676	3
21109	854	15	205	21	20	\N	R	22	47	\N	\N	25	20	00:01:57.126	6
21110	854	30	131	7	8	\N	R	23	28	\N	\N	26	9	00:01:53.096	3
21111	854	10	166	24	21	\N	R	24	9	\N	\N	6	24	00:02:00.412	3
21112	855	18	1	4	2	1	1	1	53	1:30:53.427	5453427	52	1	00:01:36.568	1
21113	855	4	6	5	5	2	2	2	53	+1.160	5454587	50	4	00:01:36.682	1
21114	855	20	9	1	1	3	3	3	53	+2.006	5455433	52	6	00:01:36.916	1
21115	855	17	9	2	6	4	4	4	53	+8.071	5461498	47	5	00:01:36.828	1
21116	855	1	1	3	3	5	5	5	53	+24.268	5477695	49	9	00:01:37.645	1
21117	855	30	131	7	8	6	6	6	53	+27.120	5480547	53	12	00:01:37.916	1
21118	855	13	6	6	4	7	7	7	53	+28.240	5481667	50	11	00:01:37.8	1
21119	855	815	15	17	17	8	8	8	53	+39.377	5492804	39	2	00:01:36.569	1
21120	855	808	4	10	10	9	9	9	53	+42.607	5496034	47	7	00:01:37.053	1
21121	855	3	131	8	23	10	10	10	53	+44.322	5497749	50	3	00:01:36.614	1
21122	855	16	10	14	11	11	11	11	53	+54.447	5507874	43	14	00:01:38.133	1
21123	855	814	10	15	12	12	12	12	53	+1:02.326	5515753	43	13	00:01:37.97	1
21124	855	155	15	16	7	13	13	13	53	+1:03.705	5517132	44	19	00:01:39.724	1
21125	855	813	3	12	14	14	14	14	53	+1:04.194	5517621	50	10	00:01:37.645	1
21126	855	153	5	19	16	15	15	15	53	+1:06.623	5520050	41	8	00:01:37.411	1
21127	855	811	4	9	9	16	16	16	53	+1:12.628	5526055	42	15	00:01:38.407	1
21128	855	22	3	11	13	17	17	17	53	+1:14.191	5527618	53	16	00:01:39.08	1
21129	855	5	205	20	18	18	18	18	53	+1:27.824	5541251	50	17	00:01:39.297	1
21130	855	15	205	21	19	19	19	19	53	+1:36.140	5549567	49	18	00:01:39.561	1
21131	855	10	166	24	21	20	20	20	51	\N	\N	46	21	00:01:41.704	12
21132	855	816	166	25	20	21	21	21	51	\N	\N	45	22	00:01:41.794	12
21133	855	817	164	22	22	22	22	22	51	\N	\N	49	20	00:01:41.437	12
21134	855	24	164	23	24	23	23	23	50	\N	\N	37	24	00:01:42.409	13
21135	855	67	5	18	15	\N	R	24	11	\N	\N	6	23	00:01:42.107	36
21136	856	20	9	1	2	1	1	1	55	1:38:01.994	5881994	55	1	00:01:39.605	1
21137	856	1	1	3	1	2	2	2	55	+12.019	5894013	54	3	00:01:40.459	1
21138	856	17	9	2	4	3	3	3	55	+12.477	5894471	55	2	00:01:40.294	1
21139	856	18	1	4	3	4	4	4	55	+14.694	5896688	55	7	00:01:40.709	1
21140	856	4	6	5	6	5	5	5	55	+15.689	5897683	41	6	00:01:40.547	1
21141	856	13	6	6	5	6	6	6	55	+25.133	5907127	51	5	00:01:40.541	1
21142	856	153	5	19	11	7	7	7	55	+49.538	5931532	55	8	00:01:40.94	1
21143	856	3	131	8	7	8	8	8	55	+54.053	5936047	49	9	00:01:41.77	1
21144	856	67	5	18	13	9	9	9	55	+1:02.762	5944756	50	4	00:01:40.537	1
21145	856	814	10	15	9	10	10	10	55	+1:08.602	5950596	50	12	00:01:42.102	1
21146	856	16	10	14	10	11	11	11	55	+1:11.229	5953223	49	10	00:01:42.014	1
21147	856	22	3	11	18	12	12	12	55	+1:33.068	5975062	54	13	00:01:42.371	1
21148	856	811	4	9	15	13	13	13	54	\N	\N	41	16	00:01:42.549	11
21149	856	5	205	20	19	14	14	14	54	\N	\N	52	15	00:01:42.456	11
21150	856	155	15	16	14	15	15	15	54	\N	\N	45	11	00:01:42.08	11
21151	856	815	15	17	17	16	16	16	54	\N	\N	39	14	00:01:42.425	11
21152	856	15	205	21	20	17	17	17	54	\N	\N	46	17	00:01:43.009	11
21153	856	10	166	24	21	18	18	18	54	\N	\N	53	18	00:01:44.536	11
21154	856	817	164	22	24	19	19	19	54	\N	\N	53	21	00:01:44.87	11
21155	856	816	166	25	22	20	20	20	54	\N	\N	53	20	00:01:44.746	11
21156	856	24	164	23	23	21	21	21	52	\N	\N	45	24	00:01:46.173	13
21157	856	813	3	12	16	\N	R	22	30	\N	\N	26	19	00:01:44.689	8
21158	856	808	4	10	8	\N	R	23	16	\N	\N	10	23	00:01:45.469	4
21159	856	30	131	7	12	\N	R	24	15	\N	\N	13	22	00:01:45.327	4
21160	857	20	9	1	1	1	1	1	60	1:30:35.002	5435002	60	1	00:01:27.249	1
21161	857	18	1	4	4	2	2	2	60	+8.433	5443435	60	4	00:01:27.967	1
21162	857	4	6	5	3	3	3	3	60	+24.301	5459303	58	3	00:01:27.953	1
21163	857	17	9	2	2	4	4	4	60	+25.529	5460531	59	2	00:01:27.52	1
21164	857	30	131	7	11	5	5	5	60	+1:05.421	5500423	48	5	00:01:28.549	1
21165	857	3	131	8	7	6	6	6	60	+1:06.851	5501853	59	6	00:01:28.6	1
21166	857	1	1	3	5	7	7	7	60	+1:24.183	5519185	58	9	00:01:28.721	1
21167	857	153	5	19	10	8	8	8	59	\N	\N	57	10	00:01:29.239	11
21168	857	16	10	14	8	9	9	9	59	\N	\N	59	12	00:01:29.289	11
21169	857	815	15	17	20	10	10	10	59	\N	\N	58	14	00:01:29.345	11
21170	857	808	4	10	16	11	11	11	59	\N	\N	58	11	00:01:29.289	11
21171	857	811	4	9	14	12	12	12	59	\N	\N	55	13	00:01:29.31	11
21172	857	814	10	15	12	13	13	13	59	\N	\N	59	8	00:01:28.679	11
21173	857	5	205	20	18	14	14	14	58	\N	\N	58	16	00:01:30.294	12
21174	857	22	3	11	15	15	15	15	58	\N	\N	56	7	00:01:28.635	12
21175	857	816	166	25	21	16	16	16	57	\N	\N	51	21	00:01:31.99	13
21176	857	39	164	22	24	17	17	17	57	\N	\N	44	20	00:01:31.988	13
21177	857	817	164	23	23	18	18	18	57	\N	\N	49	18	00:01:31.674	13
21178	857	15	205	21	19	19	19	19	55	\N	\N	52	19	00:01:31.691	15
21179	857	13	6	6	6	\N	R	20	32	\N	\N	19	15	00:01:30.243	22
21180	857	67	5	18	9	\N	R	21	24	\N	\N	23	17	00:01:30.956	5
21181	857	813	3	12	13	\N	R	22	12	\N	\N	12	22	00:01:33.573	6
21182	857	10	166	24	22	\N	R	23	2	\N	\N	2	23	00:02:09.008	4
21183	857	155	15	16	17	\N	R	24	0	\N	\N	\N	0	\N	4
21184	858	1	1	3	2	1	1	1	55	1:37:11.886	5831886	51	3	00:01:43.461	1
21185	858	4	6	5	5	2	2	2	55	+8.457	5840343	41	6	00:01:43.914	1
21186	858	18	1	4	3	3	3	3	55	+25.881	5857767	51	2	00:01:43.154	1
21187	858	17	9	2	4	4	4	4	55	+35.784	5867670	51	1	00:01:42.612	1
21188	858	13	6	6	6	5	5	5	55	+50.578	5882464	51	10	00:01:44.288	1
21189	858	3	131	8	7	6	6	6	55	+52.317	5884203	55	7	00:01:43.993	1
21190	858	30	131	7	8	7	7	7	55	+1:15.964	5907850	48	15	00:01:44.916	1
21191	858	16	10	14	9	8	8	8	55	+1:17.122	5909008	53	14	00:01:44.709	1
21192	858	814	10	15	10	9	9	9	55	+1:41.087	5932973	49	9	00:01:44.12	1
21193	858	155	15	16	16	10	10	10	54	\N	\N	47	4	00:01:43.521	11
21194	858	815	15	17	11	11	11	11	54	\N	\N	41	12	00:01:44.566	11
21195	858	22	3	11	24	12	12	12	54	\N	\N	50	11	00:01:44.438	11
21196	858	808	4	10	12	13	13	13	54	\N	\N	52	5	00:01:43.673	11
21197	858	813	3	12	23	14	14	14	54	\N	\N	52	13	00:01:44.628	11
21198	858	153	5	19	15	15	15	15	54	\N	\N	47	8	00:01:44.093	11
21199	858	811	4	9	14	16	16	16	54	\N	\N	32	16	00:01:46.15	11
21200	858	5	205	20	17	17	17	17	54	\N	\N	50	17	00:01:46.61	11
21201	858	15	205	21	18	18	18	18	53	\N	\N	36	19	00:01:47.444	12
21202	858	10	166	24	19	19	19	19	53	\N	\N	42	20	00:01:48.085	12
21203	858	24	164	23	22	20	20	20	53	\N	\N	52	22	00:01:49.242	12
21204	858	817	164	22	20	\N	R	21	48	\N	\N	35	21	00:01:48.274	26
21205	858	67	5	18	13	\N	R	22	19	\N	\N	17	18	00:01:47.094	9
21206	858	816	166	25	21	\N	R	23	18	\N	\N	16	23	00:01:51.196	23
21207	858	20	9	1	1	\N	R	24	1	\N	\N	\N	0	\N	29
21208	859	17	9	2	2	1	1	1	71	1:32:17.464	5537464	71	1	00:01:15.324	1
21209	859	20	9	1	1	2	2	2	71	+16.983	5554447	68	3	00:01:16.076	1
21210	859	18	1	4	3	3	3	3	71	+27.638	5565102	63	2	00:01:15.58	1
21211	859	4	6	5	5	4	4	4	71	+35.048	5572512	65	4	00:01:16.181	1
21212	859	13	6	6	7	5	5	5	71	+1:06.733	5604197	64	12	00:01:17.271	1
21213	859	16	10	14	8	6	6	6	70	\N	\N	36	8	00:01:17.161	11
21214	859	3	131	8	6	7	7	7	70	\N	\N	45	10	00:01:17.207	11
21215	859	814	10	15	11	8	8	8	70	\N	\N	64	14	00:01:17.452	11
21216	859	155	15	16	16	9	9	9	70	\N	\N	55	15	00:01:17.644	11
21217	859	808	4	10	15	10	10	10	70	\N	\N	58	7	00:01:17.011	11
21218	859	153	5	19	13	11	11	11	70	\N	\N	55	9	00:01:17.162	11
21219	859	67	5	18	14	12	12	12	70	\N	\N	59	13	00:01:17.428	11
21220	859	815	15	17	17	13	13	13	70	\N	\N	63	16	00:01:17.78	11
21221	859	22	3	11	12	14	14	14	70	\N	\N	70	6	00:01:16.684	11
21222	859	30	131	7	10	15	15	15	70	\N	\N	62	5	00:01:16.681	11
21223	859	5	205	20	19	16	16	16	69	\N	\N	69	17	00:01:18.023	12
21224	859	811	4	9	9	17	17	17	69	\N	\N	62	18	00:01:18.274	12
21225	859	15	205	21	20	18	18	18	69	\N	\N	47	19	00:01:18.596	12
21226	859	816	166	25	23	19	19	19	68	\N	\N	60	22	00:01:19.902	13
21227	859	817	164	22	22	20	20	20	68	\N	\N	64	20	00:01:19.649	13
21228	859	24	164	23	21	\N	R	21	61	\N	\N	60	23	00:01:20.648	31
21229	859	1	1	3	4	\N	R	22	46	\N	\N	35	11	00:01:17.209	6
21230	859	813	3	12	18	\N	R	23	26	\N	\N	26	21	00:01:19.706	31
21231	859	10	166	24	24	\N	R	24	21	\N	\N	14	24	00:01:21.773	31
21232	860	18	1	3	2	1	1	1	58	1:34:09.565	5649565	56	1	00:01:29.187	1
21233	860	20	9	1	6	2	2	2	58	+2.139	5651704	57	2	00:01:29.417	1
21234	860	1	1	4	1	3	3	3	58	+4.075	5653640	57	4	00:01:29.538	1
21235	860	17	9	2	5	4	4	4	58	+4.547	5654112	57	3	00:01:29.438	1
21236	860	4	6	5	12	5	5	5	58	+21.565	5671130	52	7	00:01:30.277	1
21237	860	155	15	14	13	6	6	6	58	+36.766	5686331	55	10	00:01:30.62	1
21238	860	8	208	9	17	7	7	7	58	+38.014	5687579	50	11	00:01:30.759	1
21239	860	815	15	15	22	8	8	8	58	+39.458	5689023	46	12	00:01:30.843	1
21240	860	817	5	16	10	9	9	9	58	+39.556	5689121	53	8	00:01:30.592	1
21241	860	814	10	11	15	10	10	10	58	+39.737	5689302	57	9	00:01:30.605	1
21242	860	818	5	17	11	11	11	11	58	+39.848	5689413	52	6	00:01:30.274	1
21243	860	3	131	8	7	12	12	12	58	+57.642	5707207	53	14	00:01:30.931	1
21244	860	813	3	18	8	13	13	13	57	\N	\N	53	5	00:01:30.254	3
21245	860	10	206	24	20	14	14	14	57	\N	\N	43	19	00:01:34.253	11
21246	860	819	206	25	21	15	15	15	53	\N	\N	45	20	00:01:35.011	15
21247	860	811	3	19	14	16	16	16	52	\N	\N	49	13	00:01:30.855	4
21248	860	13	6	6	16	\N	R	17	46	\N	\N	46	15	00:01:31.94	4
21249	860	5	207	20	18	\N	R	18	38	\N	\N	26	17	00:01:33.693	22
21250	860	808	207	21	19	\N	R	19	34	\N	\N	27	16	00:01:33.214	38
21251	860	30	131	7	4	\N	R	20	10	\N	\N	4	18	00:01:34.021	6
21252	860	154	208	10	3	\N	R	21	1	\N	\N	\N	0	\N	4
21253	860	807	10	12	9	\N	R	22	0	\N	\N	\N	0	\N	4
21254	860	37	164	22	0	\N	F	23	0	\N	\N	\N	0	\N	81
21255	860	39	164	23	0	\N	F	24	0	\N	\N	\N	0	\N	81
21256	861	4	6	5	8	1	1	1	56	2:44:51.812	9891812	53	7	00:01:41.68	1
21257	861	815	15	15	9	2	2	2	56	+2.263	9894075	54	3	00:01:41.021	1
21258	861	1	1	4	1	3	3	3	56	+14.591	9906403	50	6	00:01:41.539	1
21259	861	17	9	2	4	4	4	4	56	+17.688	9909500	52	2	00:01:41.017	1
21260	861	8	208	9	10	5	5	5	56	+29.456	9921268	53	1	00:01:40.722	1
21261	861	811	3	19	13	6	6	6	56	+37.667	9929479	55	5	00:01:41.404	1
21262	861	814	10	11	14	7	7	7	56	+44.412	9936224	55	10	00:01:41.819	1
21263	861	818	5	17	18	8	8	8	56	+46.985	9938797	55	12	00:01:41.922	1
21264	861	807	10	12	16	9	9	9	56	+47.892	9939704	51	15	00:01:42.173	1
21265	861	30	131	7	3	10	10	10	56	+49.996	9941808	53	9	00:01:41.76	1
21266	861	20	9	1	5	11	11	11	56	+1:15.527	9967339	50	4	00:01:41.342	1
21267	861	817	5	16	15	12	12	12	56	+1:16.828	9968640	54	8	00:01:41.756	1
21268	861	3	131	8	7	13	13	13	56	+1:18.593	9970405	51	11	00:01:41.863	1
21269	861	18	1	3	2	14	14	14	56	+1:19.719	9971531	50	14	00:01:42.1	1
21270	861	13	6	6	12	15	15	15	56	+1:37.319	9989131	56	13	00:01:42.051	1
21271	861	808	207	21	19	16	16	16	55	\N	\N	52	17	00:01:43.513	11
21272	861	10	206	24	20	17	17	17	55	\N	\N	50	20	00:01:44.757	11
21273	861	5	207	20	24	18	18	18	55	\N	\N	54	18	00:01:43.803	11
21274	861	813	3	18	11	19	19	19	54	\N	\N	51	16	00:01:42.237	5
21275	861	819	206	25	21	20	20	20	54	\N	\N	50	21	00:01:44.813	12
21276	861	39	164	23	23	21	21	21	54	\N	\N	52	22	00:01:45.909	12
21277	861	37	164	22	22	22	22	22	54	\N	\N	54	23	00:01:46.244	12
21278	861	155	15	14	17	\N	R	23	46	\N	\N	44	19	00:01:44.202	31
21279	861	154	208	10	6	\N	R	24	3	\N	\N	2	24	00:02:08.464	4
21280	862	3	131	8	1	1	1	1	56	1:36:26.929	5786929	40	8	00:01:40.967	1
21281	862	18	1	3	5	2	2	2	56	+20.626	5807555	56	3	00:01:40.422	1
21282	862	1	1	4	7	3	3	3	56	+26.012	5812941	40	6	00:01:40.53	1
21283	862	17	9	2	6	4	4	4	56	+27.924	5814853	52	5	00:01:40.49	1
21284	862	20	9	1	11	5	5	5	56	+30.483	5817412	33	7	00:01:40.601	1
21285	862	154	208	10	10	6	6	6	56	+31.491	5818420	35	11	00:01:41.12	1
21286	862	811	3	19	14	7	7	7	56	+34.597	5821526	37	16	00:01:41.293	1
21287	862	813	3	18	13	8	8	8	56	+35.643	5822572	36	4	00:01:40.482	1
21288	862	4	6	5	9	9	9	9	56	+37.256	5824185	41	12	00:01:41.152	1
21289	862	155	15	14	3	10	10	10	56	+38.720	5825649	40	1	00:01:39.96	1
21290	862	815	15	15	8	11	11	11	56	+41.066	5827995	37	10	00:01:41.071	1
21291	862	814	10	11	15	12	12	12	56	+42.273	5829202	40	17	00:01:41.498	1
21292	862	13	6	6	12	13	13	13	56	+42.779	5829708	48	14	00:01:41.24	1
21293	862	8	208	9	4	14	14	14	56	+50.573	5837502	43	18	00:01:41.794	1
21294	862	807	10	12	16	15	15	15	56	+51.213	5838142	48	9	00:01:40.977	1
21295	862	818	5	17	24	16	16	16	56	+51.756	5838685	48	2	00:01:40.019	1
21296	862	817	5	16	17	17	17	17	56	+1:03.156	5850085	40	15	00:01:41.251	1
21297	862	808	207	21	19	18	18	18	55	\N	\N	38	19	00:01:42.385	11
21298	862	10	206	24	20	19	19	19	55	\N	\N	41	21	00:01:42.748	11
21299	862	819	206	25	21	20	20	20	55	\N	\N	39	20	00:01:42.621	11
21300	862	37	164	22	22	21	21	21	55	\N	\N	54	22	00:01:43.61	11
21301	862	39	164	23	23	22	22	22	54	\N	\N	40	23	00:01:43.935	12
21302	862	5	207	20	18	23	23	23	53	\N	\N	53	13	00:01:41.19	13
21303	862	30	131	7	2	\N	R	24	12	\N	\N	9	24	00:01:44.109	61
21304	863	20	9	1	1	1	1	1	57	1:35:10.990	5710990	41	1	00:01:36.379	1
21305	863	8	208	9	11	2	2	2	57	+3.333	5714323	41	5	00:01:37.116	1
21306	863	154	208	10	7	3	3	3	57	+10.194	5721184	42	3	00:01:36.928	1
21307	863	17	9	2	3	4	4	4	57	+38.788	5749778	45	6	00:01:37.437	1
21308	863	3	131	8	5	5	5	5	57	+55.460	5766450	41	10	00:01:38.08	1
21309	863	814	10	11	10	6	6	6	57	+57.543	5768533	41	18	00:01:38.372	1
21310	863	4	6	5	9	7	7	7	57	+57.803	5768793	44	15	00:01:38.203	1
21311	863	1	1	4	2	8	8	8	57	+58.984	5769974	38	7	00:01:37.733	1
21312	863	13	6	6	14	9	9	9	57	+1:04.999	5775989	42	12	00:01:38.123	1
21313	863	30	131	7	22	10	10	10	57	+1:11.490	5782480	39	13	00:01:38.128	1
21314	863	815	15	15	8	11	11	11	57	+1:12.702	5783692	39	14	00:01:38.146	1
21315	863	807	10	12	13	12	12	12	57	+1:16.539	5787529	46	17	00:01:38.312	1
21316	863	155	15	14	12	13	13	13	57	+1:30.334	5801324	54	2	00:01:36.7	1
21317	863	818	5	17	17	14	14	14	57	+1:33.723	5804713	43	4	00:01:37.058	1
21318	863	817	5	16	6	15	15	15	56	\N	\N	42	8	00:01:37.903	11
21319	863	808	207	21	18	16	16	16	56	\N	\N	42	16	00:01:38.305	11
21320	863	5	207	20	16	17	17	17	56	\N	\N	43	19	00:01:38.441	11
21321	863	18	1	3	4	18	18	18	55	\N	\N	47	9	00:01:38.046	43
21322	863	10	206	24	23	19	19	19	55	\N	\N	46	23	00:01:40.323	12
21323	863	37	164	22	20	20	20	20	55	\N	\N	41	22	00:01:40.237	12
21324	863	39	164	23	24	21	21	21	55	\N	\N	48	20	00:01:39.747	12
21325	863	811	3	19	15	22	22	22	54	\N	\N	51	11	00:01:38.087	76
21326	863	813	3	18	21	\N	R	23	25	\N	\N	14	21	00:01:39.876	29
21327	863	819	206	25	19	\N	R	24	24	\N	\N	14	24	00:01:41.519	5
21328	864	813	3	18	1	1	1	1	66	1:39:09.145	5949145	26	6	00:01:27.906	1
21329	864	4	6	5	2	2	2	2	66	+3.195	5952340	46	3	00:01:27.39	1
21330	864	8	208	9	4	3	3	3	66	+3.884	5953029	50	2	00:01:26.938	1
21331	864	154	208	10	3	4	4	4	66	+14.799	5963944	53	1	00:01:26.25	1
21332	864	155	15	14	9	5	5	5	66	+1:04.641	6013786	45	8	00:01:28.266	1
21333	864	20	9	1	7	6	6	6	66	+1:07.576	6016721	65	4	00:01:27.768	1
21334	864	3	131	8	6	7	7	7	66	+1:17.919	6027064	45	7	00:01:28.15	1
21335	864	1	1	4	24	8	8	8	66	+1:18.140	6027285	50	18	00:01:28.918	1
21336	864	18	1	3	10	9	9	9	66	+1:25.246	6034391	41	14	00:01:28.624	1
21337	864	807	10	12	13	10	10	10	65	\N	\N	48	17	00:01:28.912	11
21338	864	17	9	2	11	11	11	11	65	\N	\N	44	5	00:01:27.857	11
21339	864	818	5	17	14	12	12	12	65	\N	\N	54	9	00:01:28.308	11
21340	864	817	5	16	15	13	13	13	65	\N	\N	44	12	00:01:28.587	11
21341	864	814	10	11	12	14	14	14	65	\N	\N	44	10	00:01:28.313	11
21342	864	13	6	6	16	15	15	15	65	\N	\N	47	11	00:01:28.448	11
21343	864	5	207	20	19	16	16	16	65	\N	\N	50	15	00:01:28.715	11
21344	864	808	207	21	18	17	17	17	65	\N	\N	48	16	00:01:28.773	11
21345	864	10	206	24	21	18	18	18	64	\N	\N	49	19	00:01:29.599	12
21346	864	37	164	22	22	19	19	19	63	\N	\N	54	20	00:01:30.722	13
21347	864	815	15	15	5	\N	R	20	37	\N	\N	20	13	00:01:28.605	61
21348	864	819	206	25	20	\N	R	21	35	\N	\N	29	22	00:01:31.136	26
21349	864	39	164	23	23	\N	R	22	22	\N	\N	15	24	00:01:32.903	26
21350	864	811	3	19	17	\N	R	23	12	\N	\N	10	23	00:01:31.822	4
21351	864	30	131	7	8	\N	R	24	12	\N	\N	4	21	00:01:31.089	4
21352	865	17	9	2	1	1	1	1	78	1:46:06.557	6366557	45	3	00:01:18.805	1
21353	865	3	131	8	2	2	2	2	78	+0.643	6367200	46	7	00:01:18.977	1
21354	865	4	6	5	5	3	3	3	78	+0.947	6367504	45	5	00:01:18.857	1
21355	865	20	9	1	9	4	4	4	78	+1.343	6367900	43	9	00:01:19.076	1
21356	865	1	1	4	3	5	5	5	78	+4.101	6370658	46	4	00:01:18.806	1
21357	865	13	6	6	7	6	6	6	78	+6.195	6372752	41	10	00:01:19.101	1
21358	865	814	10	11	14	7	7	7	78	+41.537	6408094	51	17	00:01:19.757	1
21359	865	807	10	12	10	8	8	8	78	+42.562	6409119	35	2	00:01:18.423	1
21360	865	8	208	9	8	9	9	9	78	+44.036	6410593	51	12	00:01:19.246	1
21361	865	811	3	19	13	10	10	10	78	+44.516	6411073	51	11	00:01:19.187	1
21362	865	815	15	15	23	11	11	11	77	\N	\N	49	1	00:01:17.296	11
21363	865	818	5	17	16	12	12	12	77	\N	\N	25	8	00:01:19.013	11
21364	865	5	207	20	17	13	13	13	77	\N	\N	76	13	00:01:19.305	11
21365	865	10	206	24	19	14	14	14	77	\N	\N	60	15	00:01:19.637	11
21366	865	39	164	23	22	15	15	15	76	\N	\N	44	19	00:01:20.286	12
21367	865	18	1	3	12	16	16	16	70	\N	\N	51	18	00:01:19.923	4
21368	865	817	5	16	15	\N	R	17	65	\N	\N	44	16	00:01:19.752	31
21369	865	819	206	25	21	\N	R	18	64	\N	\N	61	14	00:01:19.604	31
21370	865	30	131	7	6	\N	R	19	63	\N	\N	52	6	00:01:18.904	32
21371	865	808	207	21	18	\N	R	20	15	\N	\N	12	20	00:01:20.825	10
21372	865	155	15	14	11	\N	R	21	5	\N	\N	4	21	00:01:25.48	3
21373	865	37	164	22	20	\N	R	22	0	\N	\N	\N	0	\N	3
21374	865	813	3	18	24	\N	R	23	0	\N	\N	\N	0	\N	3
21375	865	154	208	10	4	\N	R	24	0	\N	\N	\N	0	\N	3
21376	866	1	1	4	2	1	1	1	70	1:32:29.586	5549586	59	6	00:01:17.02	1
21377	866	154	208	10	7	2	2	2	70	+2.513	5552099	57	11	00:01:17.264	1
21378	866	815	15	15	15	3	3	3	70	+5.260	5554846	67	3	00:01:16.414	1
21379	866	20	9	1	1	4	4	4	70	+7.295	5556881	70	1	00:01:15.752	1
21380	866	4	6	5	3	5	5	5	70	+13.411	5562997	42	15	00:01:17.82	1
21381	866	3	131	8	5	6	6	6	70	+13.842	5563428	67	7	00:01:17.06	1
21382	866	17	9	2	4	7	7	7	70	+15.085	5564671	62	8	00:01:17.131	1
21383	866	8	208	9	12	8	8	8	70	+15.567	5565153	70	5	00:01:16.764	1
21384	866	155	15	14	11	9	9	9	70	+24.432	5574018	61	12	00:01:17.464	1
21385	866	13	6	6	6	10	10	10	70	+25.272	5574858	69	2	00:01:16.182	1
21386	866	814	10	11	8	11	11	11	70	+37.693	5587279	63	10	00:01:17.219	1
21387	866	807	10	12	13	12	12	12	70	+46.236	5595822	62	9	00:01:17.202	1
21388	866	813	3	18	22	13	13	13	70	+47.052	5596638	67	13	00:01:17.489	1
21389	866	817	5	16	14	14	14	14	70	+1:04.475	5614061	70	4	00:01:16.609	1
21390	866	818	5	17	19	15	15	15	69	\N	\N	55	17	00:01:17.875	11
21391	866	18	1	3	10	16	16	16	69	\N	\N	63	16	00:01:17.843	11
21392	866	811	3	19	16	17	17	17	69	\N	\N	67	14	00:01:17.817	11
21393	866	5	207	20	17	18	18	18	69	\N	\N	62	19	00:01:18.128	11
21394	866	808	207	21	18	19	19	19	69	\N	\N	58	18	00:01:18.093	11
21395	866	819	206	25	23	20	20	20	69	\N	\N	63	21	00:01:20.632	13
21396	866	10	206	24	21	21	21	21	56	\N	\N	47	22	00:01:21.032	22
21397	866	30	131	7	9	\N	R	22	43	\N	\N	37	20	00:01:18.433	65
21398	866	37	164	22	20	\N	R	23	24	\N	\N	23	23	00:01:21.535	23
21399	866	39	164	23	24	\N	R	24	22	\N	\N	12	24	00:01:22.044	22
21400	867	4	6	5	11	1	1	1	57	1:44:16.649	6256649	40	5	00:01:43.666	1
21401	867	8	208	9	5	2	2	2	57	+6.421	6263070	43	7	00:01:43.686	1
21402	867	30	131	7	12	3	3	3	57	+12.639	6269288	43	3	00:01:43.099	1
21403	867	17	9	2	19	4	4	4	57	+13.628	6270277	40	2	00:01:42.717	1
21404	867	807	10	12	8	5	5	5	57	+19.993	6276642	40	13	00:01:44.226	1
21405	867	3	131	8	6	6	6	6	57	+21.176	6277825	54	1	00:01:42.163	1
21406	867	814	10	11	10	7	7	7	57	+22.866	6279515	45	11	00:01:44.101	1
21407	867	18	1	3	9	8	8	8	57	+24.653	6281302	48	17	00:01:44.806	1
21408	867	815	15	15	15	9	9	9	57	+27.777	6284426	43	4	00:01:43.526	1
21409	867	811	3	19	14	10	10	10	57	+35.961	6292610	44	12	00:01:44.111	1
21410	867	817	5	16	17	11	11	11	57	+37.041	6293690	44	6	00:01:43.674	1
21411	867	813	3	18	3	12	12	12	57	+54.630	6311279	43	10	00:01:44.064	1
21412	867	808	207	21	20	13	13	13	57	+1:15.871	6332520	54	14	00:01:44.253	1
21413	867	5	207	20	16	14	14	14	57	+1:34.654	6351303	40	19	00:01:45.294	1
21414	867	819	206	25	23	15	15	15	57	+1:36.551	6353200	43	22	00:01:46.701	1
21415	867	13	6	6	13	16	16	16	56	\N	\N	36	15	00:01:44.431	11
21416	867	37	164	22	21	17	17	17	56	\N	\N	36	23	00:01:46.799	11
21417	867	39	164	23	22	18	18	18	56	\N	\N	42	21	00:01:46.388	11
21418	867	1	1	4	2	19	19	19	55	\N	\N	43	9	00:01:44.007	4
21419	867	154	208	10	4	\N	R	20	40	\N	\N	38	8	00:01:43.764	40
21420	867	20	9	1	1	\N	R	21	33	\N	\N	18	16	00:01:44.555	6
21421	867	155	15	14	7	\N	R	22	33	\N	\N	22	18	00:01:45.082	4
21422	867	818	5	17	18	\N	R	23	26	\N	\N	22	20	00:01:45.491	4
21423	867	10	206	24	0	\N	W	24	0	\N	\N	\N	0	\N	54
21424	868	17	9	2	2	1	1	1	52	1:25:11.288	5111288	49	4	00:01:34.934	1
21425	868	4	6	5	1	2	2	2	52	+3.060	5114348	49	7	00:01:35.385	1
21426	868	20	9	1	4	3	3	3	52	+4.836	5116124	52	3	00:01:34.897	1
21427	868	13	6	6	5	4	4	4	52	+9.519	5120807	50	5	00:01:35.041	1
21428	868	8	208	9	6	5	5	5	52	+10.314	5121602	50	1	00:01:34.661	1
21429	868	154	208	10	9	6	6	6	52	+17.101	5128389	50	2	00:01:34.884	1
21430	868	30	131	7	3	7	7	7	52	+29.153	5140441	52	6	00:01:35.191	1
21431	868	1	1	4	8	8	8	8	52	+36.463	5147751	44	15	00:01:36.173	1
21432	868	811	3	19	13	9	9	9	52	+43.347	5154635	48	12	00:01:35.863	1
21433	868	18	1	3	16	10	10	10	52	+44.444	5155732	52	14	00:01:36.086	1
21434	868	155	15	14	17	11	11	11	52	+45.370	5156658	48	9	00:01:35.478	1
21435	868	807	10	12	14	12	12	12	52	+47.856	5159144	37	13	00:01:35.981	1
21436	868	817	5	16	12	13	13	13	52	+51.241	5162529	49	8	00:01:35.448	1
21437	868	818	5	17	23	14	14	14	52	+53.313	5164601	49	10	00:01:35.514	1
21438	868	3	131	8	11	15	15	15	52	+57.394	5168682	49	11	00:01:35.75	1
21439	868	813	3	18	7	16	16	16	51	\N	\N	34	17	00:01:37.515	11
21440	868	5	207	20	19	17	17	17	51	\N	\N	37	19	00:01:38.05	11
21441	868	10	206	24	20	18	18	18	51	\N	\N	50	16	00:01:37.422	11
21442	868	819	206	25	24	19	19	19	51	\N	\N	50	18	00:01:38.008	11
21443	868	37	164	22	21	20	20	20	50	\N	\N	44	21	00:01:39.618	12
21444	868	39	164	23	22	21	21	21	50	\N	\N	50	20	00:01:38.339	12
21445	868	815	15	15	15	\N	R	22	11	\N	\N	3	22	00:01:39.781	4
21446	868	814	10	11	10	\N	R	23	2	\N	\N	\N	0	\N	4
21447	868	808	207	21	18	\N	W	24	0	\N	\N	\N	0	\N	5
21448	869	4	6	5	1	1	1	1	67	1:31:05.862	5465862	66	2	00:01:19.044	1
21449	869	18	1	3	6	2	2	2	67	+6.949	5472811	67	8	00:01:19.469	1
21450	869	8	208	9	10	3	3	3	67	+16.409	5482271	62	13	00:01:19.719	1
21451	869	155	15	14	12	4	4	4	67	+21.925	5487787	56	9	00:01:19.485	1
21452	869	20	9	1	2	5	5	5	67	+23.732	5489594	61	4	00:01:19.161	1
21453	869	815	15	15	17	6	6	6	67	+27.896	5493758	62	6	00:01:19.27	1
21454	869	30	131	7	3	7	7	7	67	+28.970	5494832	57	1	00:01:18.725	1
21455	869	17	9	2	8	8	8	8	67	+46.941	5512803	59	14	00:01:19.794	1
21456	869	807	10	12	4	9	9	9	67	+48.162	5514024	56	7	00:01:19.372	1
21457	869	3	131	8	21	10	10	10	67	+48.889	5514751	59	3	00:01:19.105	1
21458	869	814	10	11	9	11	11	11	67	+59.227	5525089	67	12	00:01:19.717	1
21459	869	13	6	6	13	12	12	12	67	+71.428	5537290	67	5	00:01:19.225	1
21460	869	817	5	16	11	13	13	13	67	+76.829	5542691	44	18	00:01:20.066	1
21461	869	818	5	17	15	14	14	14	67	+76.965	5542827	59	11	00:01:19.645	1
21462	869	813	3	18	5	15	15	15	66	\N	\N	59	10	00:01:19.607	11
21463	869	808	207	21	18	16	16	16	66	\N	\N	62	16	00:01:19.997	11
21464	869	811	3	19	14	17	17	17	66	\N	\N	62	15	00:01:19.894	11
21465	869	154	208	10	19	18	18	18	66	\N	\N	60	17	00:01:20.013	11
21466	869	5	207	20	16	19	19	19	65	\N	\N	61	20	00:01:20.596	12
21467	869	819	206	25	20	20	20	20	65	\N	\N	45	21	00:01:21.753	12
21468	869	37	164	22	23	21	21	21	64	\N	\N	51	23	00:01:22.407	13
21469	869	10	206	24	22	22	22	22	64	\N	\N	54	24	00:01:22.778	13
21470	869	39	164	23	24	23	23	23	64	\N	\N	55	22	00:01:21.788	13
21471	869	1	1	4	7	\N	R	24	56	\N	\N	34	19	00:01:20.091	45
21472	870	1	1	4	1	1	1	1	69	1:41:05.503	6065503	65	4	00:01:25.677	1
21473	870	8	208	9	5	2	2	2	69	+1.032	6066535	41	6	00:01:25.728	1
21474	870	154	208	10	2	3	3	3	69	+10.518	6076021	59	13	00:01:26.05	1
21475	870	20	9	1	3	4	4	4	69	+11.614	6077117	68	1	00:01:24.136	1
21476	870	4	6	5	6	5	5	5	69	+26.653	6092156	65	7	00:01:25.738	1
21477	870	18	1	3	4	6	6	6	69	+30.243	6095746	58	10	00:01:25.831	1
21478	870	811	3	19	9	7	7	7	69	+33.899	6099402	65	16	00:01:26.248	1
21479	870	17	9	2	11	8	8	8	69	+34.458	6099961	41	3	00:01:25.402	1
21480	870	13	6	6	7	9	9	9	69	+38.350	6103853	54	11	00:01:25.92	1
21481	870	3	131	8	13	10	10	10	69	+51.234	6116737	58	9	00:01:25.83	1
21482	870	807	10	12	10	11	11	11	69	+57.283	6122786	60	15	00:01:26.073	1
21483	870	814	10	11	12	12	12	12	69	+1:02.887	6128390	57	12	00:01:25.976	1
21484	870	813	3	18	8	13	13	13	69	+1:03.606	6129109	63	5	00:01:25.723	1
21485	870	815	15	15	14	14	14	14	69	+1:04.494	6129997	65	2	00:01:25.218	1
21486	870	817	5	16	18	15	15	15	68	\N	\N	59	17	00:01:26.508	11
21487	870	818	5	17	16	16	16	16	68	\N	\N	66	14	00:01:26.061	11
21488	870	5	207	20	19	17	17	17	68	\N	\N	62	18	00:01:26.595	11
21489	870	155	15	14	15	18	18	18	67	\N	\N	61	8	00:01:25.745	12
21490	870	808	207	21	20	19	19	19	67	\N	\N	59	20	00:01:27.629	12
21491	870	819	206	25	21	20	20	20	67	\N	\N	22	22	00:01:28.727	12
21492	870	10	206	24	22	21	21	21	66	\N	\N	55	21	00:01:28.447	13
21493	870	37	164	22	23	22	22	22	66	\N	\N	56	23	00:01:28.765	13
21494	870	39	164	23	24	\N	R	23	60	\N	\N	56	24	00:01:29.506	22
21495	870	30	131	7	17	\N	R	24	58	\N	\N	56	19	00:01:26.778	45
21496	871	18	1	3	1	1	1	1	44	1:29:08.530	5348530	40	10	00:01:54.293	1
21497	871	20	9	1	10	2	2	2	44	+13.624	5362154	39	9	00:01:54.198	1
21498	871	8	208	9	3	3	3	3	44	+25.334	5373864	34	5	00:01:53.64	1
21499	871	807	10	12	11	4	4	4	44	+27.843	5376373	40	6	00:01:53.76	1
21500	871	13	6	6	14	5	5	5	44	+29.845	5378375	30	3	00:01:53.464	1
21501	871	17	9	2	12	6	6	6	44	+31.244	5379774	42	7	00:01:53.768	1
21502	871	30	131	7	13	7	7	7	44	+53.374	5401904	37	4	00:01:53.507	1
21503	871	818	5	17	15	8	8	8	44	+58.865	5407395	31	8	00:01:53.995	1
21504	871	817	5	16	16	9	9	9	44	+62.982	5411512	42	12	00:01:54.605	1
21505	871	814	10	11	9	10	10	10	44	+63.783	5412313	28	11	00:01:54.562	1
21506	871	3	131	8	23	11	11	11	44	+65.111	5413641	39	2	00:01:53.073	1
21507	871	811	3	19	17	12	12	12	44	+71.529	5420059	43	1	00:01:52.822	1
21508	871	155	15	14	2	13	13	13	44	+116.119	5464649	26	13	00:01:55.598	1
21509	871	808	207	21	19	14	14	14	43	\N	\N	28	15	00:01:56.741	11
21510	871	10	206	24	20	15	15	15	43	\N	\N	30	16	00:01:56.956	11
21511	871	819	206	25	22	16	16	16	43	\N	\N	27	18	00:01:57.939	11
21512	871	5	207	20	18	17	17	17	43	\N	\N	33	14	00:01:56.475	11
21513	871	37	164	22	21	18	18	18	43	\N	\N	30	17	00:01:57.315	11
21514	871	39	164	23	24	\N	R	19	29	\N	\N	16	19	00:01:59.113	20
21515	871	813	3	18	6	\N	R	20	4	\N	\N	4	20	00:02:56.181	4
21516	871	815	15	15	4	\N	R	21	0	\N	\N	\N	0	\N	4
21517	871	4	6	5	5	\N	R	22	0	\N	\N	\N	0	\N	4
21518	871	1	1	4	7	\N	R	23	0	\N	\N	\N	0	\N	4
21519	871	154	208	10	8	\N	R	24	0	\N	\N	\N	0	\N	4
21520	872	1	1	4	1	1	1	1	53	1:19:41.221	4781221	52	5	00:01:28.427	1
21521	872	815	15	15	12	2	2	2	53	+4.356	4785577	53	2	00:01:27.562	1
21522	872	4	6	5	10	3	3	3	53	+20.594	4801815	44	11	00:01:28.835	1
21523	872	13	6	6	3	4	4	4	53	+29.667	4810888	33	12	00:01:28.914	1
21524	872	8	208	9	7	5	5	5	53	+30.881	4812102	52	17	00:01:29.109	1
21525	872	30	131	7	4	6	6	6	53	+31.259	4812480	51	3	00:01:27.718	1
21526	872	3	131	8	6	7	7	7	53	+33.550	4814771	53	1	00:01:27.239	1
21527	872	814	10	11	9	8	8	8	53	+41.057	4822278	51	16	00:01:29.068	1
21528	872	155	15	14	8	9	9	9	53	+43.898	4825119	39	14	00:01:29.032	1
21529	872	811	3	19	13	10	10	10	53	+48.144	4829365	52	10	00:01:28.742	1
21530	872	813	3	18	22	11	11	11	53	+48.682	4829903	51	4	00:01:28.053	1
21531	872	817	5	16	14	12	12	12	53	+50.316	4831537	46	7	00:01:28.621	1
21532	872	816	208	10	15	13	13	13	53	+1:15.861	4857082	52	8	00:01:28.677	1
21533	872	5	207	20	17	14	14	14	52	\N	\N	46	19	00:01:29.399	11
21534	872	808	207	21	18	15	15	15	52	\N	\N	46	15	00:01:29.066	11
21535	872	819	206	25	20	16	16	16	52	\N	\N	44	20	00:01:29.753	11
21536	872	10	206	24	19	17	17	17	52	\N	\N	50	21	00:01:29.888	11
21537	872	37	164	22	23	18	18	18	52	\N	\N	51	22	00:01:30.398	11
21538	872	39	164	23	21	19	19	19	52	\N	\N	44	23	00:01:31.086	11
21539	872	17	9	2	11	20	20	20	51	\N	\N	43	18	00:01:29.202	76
21540	872	807	10	12	24	21	21	21	50	\N	\N	46	6	00:01:28.578	23
21541	872	20	9	1	5	22	22	22	47	\N	\N	46	9	00:01:28.713	91
21542	872	18	1	3	2	\N	R	23	32	\N	\N	31	13	00:01:28.926	32
21543	872	818	5	17	16	\N	R	24	8	\N	\N	6	24	00:01:31.962	22
21544	873	20	9	1	3	1	1	1	59	2:00:26.144	7226144	50	3	00:01:52.134	1
21545	873	18	1	3	4	2	2	2	59	+8.959 sec	7235103	47	4	00:01:52.625	1
21546	873	4	6	5	5	3	3	3	59	+15.227	7241371	53	5	00:01:52.709	1
21547	873	814	10	11	6	4	4	4	59	+19.063	7245207	54	7	00:01:52.931	1
21548	873	3	131	8	10	5	5	5	59	+34.784	7260928	55	12	00:01:53.897	1
21549	873	8	208	9	12	6	6	6	59	+35.759	7261903	53	11	00:01:53.785	1
21550	873	154	208	10	8	7	7	7	59	+36.698	7262842	56	14	00:01:54.123	1
21551	873	13	6	6	13	8	8	8	59	+42.829	7268973	47	13	00:01:53.997	1
21552	873	817	5	16	15	9	9	9	59	+45.820	7271964	53	15	00:01:54.267	1
21553	873	815	15	15	14	10	10	10	59	+50.619	7276763	51	6	00:01:52.778	1
21554	873	17	9	2	7	11	11	11	59	+87.175	7313319	53	10	00:01:53.726	1
21555	873	10	206	24	20	12	12	12	59	+91.918	7318062	30	21	00:01:56.057	1
21556	873	155	15	14	17	13	13	13	59	+97.141	7323285	52	2	00:01:51.69	1
21557	873	807	10	12	11	14	14	14	59	+99.413	7325557	52	1	00:01:51.033	1
21558	873	5	207	20	19	15	15	15	59	+107.967	7334111	48	18	00:01:55.233	1
21559	873	819	206	25	21	16	16	16	59	+132.925	7359069	37	22	00:01:56.486	1
21560	873	37	164	22	24	17	17	17	58	\N	\N	48	23	00:01:57.671	11
21561	873	811	3	19	22	18	18	18	57	\N	\N	27	9	00:01:53.61	31
21562	873	808	207	21	18	19	19	19	57	\N	\N	44	17	00:01:55.14	12
21563	873	818	5	17	16	\N	R	20	38	\N	\N	28	8	00:01:53.51	4
21564	873	30	131	7	9	\N	R	21	38	\N	\N	26	20	00:01:56.047	4
21565	873	813	3	18	2	\N	R	22	36	\N	\N	27	16	00:01:55.12	9
21566	873	39	164	23	23	\N	R	23	30	\N	\N	26	24	00:01:58.507	3
21567	873	1	1	4	1	\N	R	24	22	\N	\N	14	19	00:01:55.541	6
21568	874	20	9	1	1	1	1	1	53	1:28:56.242	5336242	52	1	00:01:35.774	1
21569	874	13	6	6	10	2	2	2	53	+20.639	5356881	50	5	00:01:36.894	1
21570	874	155	15	14	3	3	3	3	53	+24.538	5360780	52	3	00:01:36.679	1
21571	874	18	1	3	8	4	4	4	53	+25.098	5361340	51	2	00:01:36.606	1
21572	874	1	1	4	9	5	5	5	53	+46.490	5382732	45	11	00:01:37.76	1
21573	874	8	208	9	7	6	6	6	53	+50.424	5386666	49	13	00:01:37.886	1
21574	874	807	10	12	15	7	7	7	53	+51.159	5387401	46	14	00:01:37.938	1
21575	874	813	3	18	12	8	8	8	53	+52.364	5388606	45	12	00:01:37.771	1
21576	874	17	9	2	2	9	9	9	53	+54.675	5390917	49	7	00:01:37.128	1
21577	874	817	5	16	14	10	10	10	53	+66.919	5403161	50	8	00:01:37.455	1
21578	874	30	131	7	23	11	11	11	53	+67.769	5404011	43	6	00:01:36.942	1
21579	874	814	10	11	11	12	12	12	53	+83.460	5419702	48	10	00:01:37.535	1
21580	874	818	5	17	19	13	13	13	53	+88.645	5424887	39	9	00:01:37.533	1
21581	874	811	3	19	16	14	14	14	53	+88.709	5424951	44	4	00:01:36.819	1
21582	874	5	207	20	17	15	15	15	52	\N	\N	52	15	00:01:38.043	11
21583	874	10	206	24	18	16	16	16	52	\N	\N	48	18	00:01:38.756	11
21584	874	808	207	21	22	17	17	17	52	\N	\N	47	17	00:01:38.344	11
21585	874	37	164	22	20	18	18	18	52	\N	\N	50	20	00:01:39.351	11
21586	874	154	208	10	4	19	19	19	51	\N	\N	32	16	00:01:38.277	12
21587	874	819	206	25	21	\N	R	20	37	\N	\N	34	21	00:01:40.493	5
21588	874	39	164	23	24	\N	R	21	32	\N	\N	21	22	00:01:41.388	76
21589	874	815	15	15	5	\N	R	22	18	\N	\N	17	19	00:01:38.983	20
21590	874	4	6	5	6	\N	R	23	0	\N	\N	\N	0	\N	4
21591	874	3	131	8	13	\N	R	24	0	\N	\N	\N	0	\N	4
21592	875	20	9	1	2	1	1	1	55	1:36:28.651	5788651	55	5	00:01:42.499	1
21593	875	17	9	2	1	2	2	2	55	+8.231	5796882	54	1	00:01:42.037	1
21594	875	4	6	5	4	3	3	3	55	+13.944	5802595	52	3	00:01:42.442	1
21595	875	13	6	6	6	4	4	4	55	+20.168	5808819	48	2	00:01:42.242	1
21596	875	8	208	9	5	5	5	5	55	+36.739	5825390	51	11	00:01:42.822	1
21597	875	807	10	12	8	6	6	6	55	+45.301	5833952	54	6	00:01:42.645	1
21598	875	154	208	10	7	7	7	7	55	+54.812	5843463	44	10	00:01:42.783	1
21599	875	818	5	17	16	8	8	8	55	+69.589	5858240	48	8	00:01:42.721	1
21600	875	817	5	16	21	9	9	9	55	+71.787	5860438	45	12	00:01:43.148	1
21601	875	1	1	4	3	10	10	10	55	+79.692	5868343	49	9	00:01:42.721	1
21602	875	815	15	15	12	11	11	11	55	+80.062	5868713	49	4	00:01:42.495	1
21603	875	814	10	11	14	12	12	12	55	+84.448	5873099	48	15	00:01:43.517	1
21604	875	30	131	7	10	13	13	13	55	+89.241	5877892	49	13	00:01:43.184	1
21605	875	813	3	18	15	14	14	14	55	+94.924	5883575	55	7	00:01:42.679	1
21606	875	811	3	19	17	15	15	15	55	+96.902	5885553	49	14	00:01:43.411	1
21607	875	808	207	21	18	16	16	16	54	\N	\N	50	18	00:01:45.013	11
21608	875	5	207	20	19	17	17	17	54	\N	\N	43	17	00:01:44.955	11
21609	875	10	206	24	20	18	18	18	54	\N	\N	42	19	00:01:45.236	11
21610	875	819	206	25	24	19	19	19	53	\N	\N	52	16	00:01:44.462	12
21611	875	39	164	23	23	20	20	20	53	\N	\N	39	21	00:01:47.068	12
21612	875	37	164	22	22	\N	R	21	16	\N	\N	9	22	00:01:49.861	37
21613	875	155	15	14	13	\N	R	22	16	\N	\N	3	20	00:01:47.066	130
21614	875	3	131	8	9	\N	R	23	1	\N	\N	\N	0	\N	4
21615	875	18	1	3	11	\N	R	24	0	\N	\N	\N	0	\N	4
21616	876	20	9	1	1	1	1	1	60	1:31:10.744	5470744	60	4	00:01:28.723	1
21617	876	4	6	5	5	2	2	2	60	+9.437	5480181	60	3	00:01:28.63	1
21618	876	17	9	2	2	3	3	3	60	+13.217	5483961	59	6	00:01:29.029	1
21619	876	1	1	4	3	4	4	4	60	+13.909	5484653	58	5	00:01:28.944	1
21620	876	18	1	3	4	5	5	5	60	+26.266	5497010	60	1	00:01:28.203	1
21621	876	13	6	6	6	6	6	6	60	+44.674	5515418	59	11	00:01:29.283	1
21622	876	8	208	9	7	7	7	7	60	+45.227	5515971	54	12	00:01:29.354	1
21623	876	807	10	12	12	8	8	8	60	+54.998	5525742	60	10	00:01:29.23	1
21624	876	154	208	10	11	9	9	9	60	+56.103	5526847	57	15	00:01:29.522	1
21625	876	811	3	19	13	10	10	10	60	+1:14.975	5545719	60	2	00:01:28.431	1
21626	876	3	131	8	10	11	11	11	60	+1:21.694	5552438	59	14	00:01:29.492	1
21627	876	814	10	11	16	12	12	12	60	+1:22.815	5553559	59	7	00:01:29.086	1
21628	876	817	5	16	15	13	13	13	60	+1:26.064	5556808	57	13	00:01:29.44	1
21629	876	155	15	14	17	14	14	14	60	+1:26.495	5557239	51	8	00:01:29.204	1
21630	876	818	5	17	18	15	15	15	59	\N	\N	59	17	00:01:30.091	11
21631	876	813	3	18	9	16	16	16	59	\N	\N	50	16	00:01:30.067	11
21632	876	808	207	21	19	17	17	17	59	\N	\N	58	19	00:01:31.163	11
21633	876	5	207	20	20	18	18	18	59	\N	\N	57	18	00:01:30.786	11
21634	876	819	206	25	24	19	19	19	59	\N	\N	55	20	00:01:31.366	11
21635	876	10	206	24	21	20	20	20	58	\N	\N	56	21	00:01:31.721	12
21636	876	39	164	23	23	21	21	21	58	\N	\N	53	22	00:01:32.161	12
21637	876	30	131	7	14	22	22	22	55	\N	\N	53	9	00:01:29.23	31
21638	876	37	164	22	22	\N	R	23	43	\N	\N	39	24	00:01:32.864	3
21639	876	815	15	15	8	\N	R	24	21	\N	\N	17	23	00:01:32.208	3
21640	877	8	208	9	4	1	1	1	55	1:45:58.667	6358667	50	3	00:01:44.458	1
21641	877	4	6	5	6	2	2	2	55	+0.852	6359519	53	2	00:01:44.09	1
21642	877	20	9	1	24	3	3	3	55	+4.163	6362830	54	1	00:01:43.964	1
21643	877	18	1	3	5	4	4	4	55	+7.787	6366454	50	4	00:01:44.533	1
21644	877	813	3	18	3	5	5	5	55	+13.007	6371674	55	5	00:01:44.833	1
21645	877	155	15	14	15	6	6	6	55	+20.076	6378743	55	8	00:01:45.423	1
21646	877	13	6	6	8	7	7	7	55	+22.896	6381563	53	11	00:01:45.7	1
21647	877	811	3	19	14	8	8	8	55	+23.542	6382209	49	10	00:01:45.693	1
21648	877	814	10	11	12	9	9	9	55	+24.160	6382827	53	9	00:01:45.617	1
21649	877	817	5	16	16	10	10	10	55	+27.463	6386130	53	12	00:01:45.903	1
21650	877	30	131	7	13	11	11	11	55	+28.075	6386742	51	6	00:01:45.225	1
21651	877	818	5	17	17	12	12	12	55	+34.906	6393573	53	13	00:01:46.113	1
21652	877	5	207	20	18	13	13	13	55	+47.764	6406431	51	15	00:01:47.115	1
21653	877	10	206	24	21	14	14	14	55	+56.473	6415140	54	18	00:01:47.661	1
21654	877	815	15	15	11	15	15	15	55	+56.768	6415435	54	7	00:01:45.41	1
21655	877	808	207	21	20	16	16	16	55	+64.595	6423262	50	19	00:01:48.308	1
21656	877	37	164	22	22	17	17	17	55	+71.778	6430445	47	20	00:01:48.619	1
21657	877	819	206	25	19	\N	R	18	41	\N	\N	33	21	00:01:49.079	31
21658	877	154	208	10	9	\N	R	19	37	\N	\N	36	17	00:01:47.521	4
21659	877	17	9	2	2	\N	R	20	37	\N	\N	32	14	00:01:46.959	4
21660	877	1	1	4	1	\N	R	21	19	\N	\N	19	16	00:01:47.266	10
21661	877	39	164	23	23	\N	R	22	7	\N	\N	6	23	00:01:52.238	4
21662	877	3	131	8	7	\N	R	23	7	\N	\N	4	22	00:01:49.34	4
21663	877	807	10	12	10	\N	R	24	0	\N	\N	\N	0	\N	4
21664	878	1	1	4	2	1	1	1	56	1:35:55.269	5755269	55	5	00:01:39.709	1
21665	878	20	9	1	1	2	2	2	56	+0.675	5755944	56	1	00:01:39.347	1
21666	878	4	6	5	7	3	3	3	56	+39.229	5794498	56	4	00:01:39.672	1
21667	878	13	6	6	11	4	4	4	56	+46.013	5801282	56	2	00:01:39.402	1
21668	878	18	1	3	12	5	5	5	56	+56.432	5811701	54	6	00:01:40.15	1
21669	878	8	208	9	4	6	6	6	56	+64.425	5819694	56	3	00:01:39.474	1
21670	878	154	208	10	8	7	7	7	56	+70.313	5825582	55	10	00:01:40.625	1
21671	878	807	10	12	6	8	8	8	56	+73.792	5829061	53	16	00:01:41.048	1
21672	878	813	3	18	9	9	9	9	56	+74.525	5829794	53	12	00:01:40.719	1
21673	878	811	3	19	10	10	10	10	56	+75.133	5830402	53	13	00:01:40.745	1
21674	878	815	15	15	15	11	11	11	56	+84.341	5839610	53	11	00:01:40.701	1
21675	878	817	5	16	18	12	12	12	56	+84.871	5840140	53	14	00:01:40.772	1
21676	878	3	131	8	17	13	13	13	56	+85.510	5840779	51	8	00:01:40.428	1
21677	878	155	15	14	16	14	14	14	55	\N	\N	55	7	00:01:40.315	11
21678	878	814	10	11	13	15	15	15	55	\N	\N	55	9	00:01:40.594	11
21679	878	30	131	7	5	16	16	16	55	\N	\N	54	15	00:01:40.923	11
21680	878	808	207	21	21	17	17	17	55	\N	\N	55	18	00:01:42.824	11
21681	878	5	207	20	22	18	18	18	55	\N	\N	50	19	00:01:43.072	11
21682	878	10	206	24	19	19	19	19	55	\N	\N	40	20	00:01:43.324	11
21683	878	819	206	25	20	20	20	20	54	\N	\N	54	17	00:01:42.481	12
21684	878	37	164	22	23	21	21	21	54	\N	\N	43	23	00:01:44.664	12
21685	878	39	164	23	24	22	22	22	54	\N	\N	51	22	00:01:44.508	12
21686	878	17	9	2	3	\N	R	23	16	\N	\N	13	21	00:01:43.599	91
21687	878	818	5	17	14	\N	R	24	14	\N	\N	12	24	00:01:44.775	22
21688	879	18	1	3	2	1	1	1	71	1:45:22.656	6322656	37	2	00:01:18.108	1
21689	879	4	6	5	7	2	2	2	71	+2.754	6325410	36	4	00:01:18.623	1
21690	879	13	6	6	5	3	3	3	71	+3.615	6326271	37	5	00:01:18.879	1
21691	879	17	9	2	3	4	4	4	71	+4.936	6327592	39	6	00:01:18.903	1
21692	879	807	10	12	6	5	5	5	71	+5.708	6328364	38	3	00:01:18.21	1
21693	879	20	9	1	4	6	6	6	71	+9.453	6332109	36	9	00:01:19.09	1
21694	879	30	131	7	13	7	7	7	71	+11.907	6334563	37	15	00:01:20.158	1
21695	879	818	5	17	17	8	8	8	71	+28.653	6351309	39	8	00:01:18.983	1
21696	879	155	15	14	14	9	9	9	71	+31.250	6353906	35	7	00:01:18.973	1
21697	879	8	208	9	8	10	10	10	70	\N	\N	34	13	00:01:19.444	11
21698	879	808	207	21	19	11	11	11	70	\N	\N	39	18	00:01:20.528	11
21699	879	819	206	25	22	12	12	12	70	\N	\N	36	17	00:01:20.31	11
21700	879	817	5	16	15	13	13	13	70	\N	\N	36	11	00:01:19.308	11
21701	879	5	207	20	20	14	14	14	70	\N	\N	39	10	00:01:19.256	11
21702	879	3	131	8	9	15	15	15	70	\N	\N	38	16	00:01:20.266	11
21703	879	10	206	24	21	16	16	16	70	\N	\N	34	14	00:01:19.686	11
21704	879	37	164	22	24	17	17	17	69	\N	\N	37	19	00:01:21.085	12
21705	879	39	164	23	23	18	18	18	69	\N	\N	40	20	00:01:21.544	12
21706	879	814	10	11	10	19	19	19	68	\N	\N	39	12	00:01:19.314	3
21707	879	1	1	4	1	\N	R	20	54	\N	\N	38	1	00:01:18.069	4
21708	879	154	208	10	18	\N	R	21	5	\N	\N	2	21	00:01:22.184	3
21709	879	813	3	18	16	\N	R	22	1	\N	\N	\N	0	\N	4
21710	879	811	3	19	11	\N	R	23	0	\N	\N	\N	0	\N	4
21711	879	815	15	15	12	\N	R	24	0	\N	\N	\N	0	\N	4
21712	880	8	208	7	7	1	1	1	58	1:30:03.225	5403225	56	1	00:01:29.274	1
21713	880	4	6	3	5	2	2	2	58	+12.451	5415676	53	3	00:01:29.56	1
21714	880	20	9	1	1	3	3	3	58	+22.346	5425571	42	10	00:01:30.409	1
21715	880	13	6	4	4	4	4	4	58	+33.577	5436802	38	8	00:01:30.239	1
21716	880	1	131	10	3	5	5	5	58	+45.561	5448786	45	5	00:01:29.759	1
21717	880	17	9	2	2	6	6	6	58	+46.800	5450025	45	4	00:01:29.732	1
21718	880	16	10	15	12	7	7	7	58	+1:05.068	5468293	49	13	00:01:30.71	1
21719	880	814	10	14	9	8	8	8	58	+1:08.449	5471674	56	15	00:01:30.894	1
21720	880	18	1	5	10	9	9	9	58	+1:21.630	5484855	41	7	00:01:30.198	1
21721	880	154	208	8	8	10	10	10	58	+1:22.759	5485984	41	9	00:01:30.395	1
21722	880	815	1	6	15	11	11	11	58	+1:23.367	5486592	46	6	00:01:29.926	1
21723	880	818	5	18	13	12	12	12	58	+1:23.857	5487082	50	2	00:01:29.498	1
21724	880	821	15	12	18	13	13	13	57	\N	\N	32	16	00:01:31.415	11
21725	880	822	3	17	16	14	14	14	57	\N	\N	42	12	00:01:30.652	11
21726	880	824	206	22	19	15	15	15	57	\N	\N	52	11	00:01:30.454	11
21727	880	819	207	20	22	16	16	16	56	\N	\N	55	19	00:01:32.261	12
21728	880	820	206	23	20	17	17	17	56	\N	\N	49	17	00:01:32.21	12
21729	880	823	207	21	21	18	18	18	56	\N	\N	39	20	00:01:32.636	12
21730	880	817	5	19	14	\N	R	19	39	\N	\N	33	14	00:01:30.881	9
21731	880	3	131	9	6	\N	R	20	26	\N	\N	18	18	00:01:32.259	10
21732	880	813	3	16	17	\N	R	21	24	\N	\N	12	21	00:01:32.915	20
21733	880	807	15	11	11	\N	W	22	0	\N	\N	\N	0	\N	69
21734	881	20	9	1	1	1	1	1	56	1:38:56.681	5936681	45	3	00:01:40.446	1
21735	881	17	9	2	5	2	2	2	56	+4.298	5940979	45	6	00:01:40.685	1
21736	881	1	131	10	4	3	3	3	56	+12.181	5948862	32	10	00:01:41.001	1
21737	881	3	131	9	6	4	4	4	56	+12.640	5949321	44	8	00:01:40.755	1
21738	881	13	6	4	2	5	5	5	56	+25.648	5962329	50	2	00:01:39.805	1
21739	881	154	208	8	11	6	6	6	56	+35.564	5972245	37	11	00:01:41.226	1
21740	881	8	208	7	10	7	7	7	56	+48.479	5985160	37	13	00:01:41.769	1
21741	881	807	15	11	12	8	8	8	56	+53.044	5989725	46	7	00:01:40.727	1
21742	881	815	1	6	9	9	9	9	56	+1:12.357	6009038	56	1	00:01:39.199	1
21743	881	818	5	18	17	10	10	10	56	+1:27.124	6023805	45	4	00:01:40.492	1
21744	881	822	3	17	18	11	11	11	56	+1:28.610	6025291	54	12	00:01:41.373	1
21745	881	821	15	12	14	12	12	12	55	\N	\N	54	9	00:01:40.929	11
21746	881	824	206	22	19	13	13	13	55	\N	\N	47	14	00:01:42.423	11
21747	881	819	207	20	20	14	14	14	55	\N	\N	51	17	00:01:42.942	11
21748	881	823	207	21	22	15	15	15	55	\N	\N	44	20	00:01:43.157	11
21749	881	820	206	23	21	16	16	16	54	\N	\N	44	19	00:01:43.15	12
21750	881	18	1	5	7	17	17	17	53	\N	\N	43	5	00:01:40.556	54
21751	881	817	5	19	13	18	18	18	51	\N	\N	35	15	00:01:42.581	31
21752	881	813	3	16	16	\N	R	19	45	\N	\N	34	21	00:01:43.465	31
21753	881	16	10	15	8	\N	R	20	27	\N	\N	24	16	00:01:42.791	61
21754	881	814	10	14	15	\N	R	21	22	\N	\N	19	18	00:01:43.094	61
21755	881	4	6	3	3	\N	R	22	1	\N	\N	\N	0	\N	4
21756	882	4	6	3	3	1	1	1	56	1:36:26.945	5786945	46	4	00:01:39.506	1
21757	882	8	208	7	2	2	2	2	56	+10.168	5797113	51	5	00:01:39.955	1
21758	882	1	131	10	1	3	3	3	56	+12.322	5799267	50	6	00:01:39.981	1
21759	882	20	9	1	9	4	4	4	56	+12.525	5799470	53	1	00:01:36.808	1
21760	882	18	1	5	8	5	5	5	56	+35.285	5822230	56	2	00:01:38.058	1
21761	882	13	6	4	5	6	6	6	56	+40.827	5827772	55	10	00:01:40.284	1
21762	882	817	5	19	7	7	7	7	56	+42.691	5829636	55	9	00:01:40.24	1
21763	882	814	10	14	11	8	8	8	56	+51.084	5838029	55	7	00:01:40.101	1
21764	882	154	208	8	6	9	9	9	56	+53.423	5840368	55	11	00:01:40.563	1
21765	882	807	15	11	10	10	10	10	56	+56.598	5843543	31	12	00:01:40.63	1
21766	882	815	1	6	12	11	11	11	56	+1:03.860	5850805	55	14	00:01:41.281	1
21767	882	818	5	18	15	12	12	12	56	+1:12.604	5859549	56	8	00:01:40.138	1
21768	882	822	3	17	16	13	13	13	56	+1:33.861	5880806	53	3	00:01:38.2	1
21769	882	813	3	16	14	14	14	14	56	+1:35.453	5882398	54	13	00:01:40.968	1
21770	882	824	206	22	18	15	15	15	55	\N	\N	35	15	00:01:41.537	11
21771	882	819	207	20	20	16	16	16	55	\N	\N	48	17	00:01:41.997	11
21772	882	820	206	23	19	17	17	17	55	\N	\N	39	16	00:01:41.978	11
21773	882	823	207	21	21	18	18	18	55	\N	\N	42	18	00:01:42.357	11
21774	882	3	131	9	4	\N	R	19	21	\N	\N	7	19	00:01:43.378	22
21775	882	17	9	2	22	\N	R	20	15	\N	\N	12	20	00:01:43.416	36
21776	882	16	10	15	13	\N	R	21	5	\N	\N	3	21	00:01:44.257	4
21777	882	821	15	12	17	\N	R	22	4	\N	\N	2	22	00:01:44.775	4
21778	883	20	9	1	2	1	1	1	57	1:36:00.498	5760498	55	1	00:01:36.961	1
21779	883	8	208	7	8	2	2	2	57	+9.111	5769609	57	8	00:01:38.164	1
21780	883	154	208	8	11	3	3	3	57	+19.507	5780005	52	5	00:01:37.627	1
21781	883	814	10	14	5	4	4	4	57	+21.727	5782225	57	12	00:01:38.336	1
21782	883	1	131	10	9	5	5	5	57	+35.230	5795728	48	11	00:01:38.204	1
21783	883	815	1	6	12	6	6	6	57	+35.998	5796496	41	7	00:01:37.913	1
21784	883	17	9	2	7	7	7	7	57	+37.244	5797742	52	13	00:01:38.557	1
21785	883	4	6	3	3	8	8	8	57	+37.574	5798072	41	3	00:01:37.204	1
21786	883	3	131	9	1	9	9	9	57	+41.126	5801624	48	4	00:01:37.588	1
21787	883	18	1	5	10	10	10	10	57	+46.631	5807129	49	6	00:01:37.743	1
21788	883	813	3	16	17	11	11	11	57	+1:06.450	5826948	57	17	00:01:38.962	1
21789	883	807	15	11	14	12	12	12	57	+1:12.933	5833431	43	15	00:01:38.77	1
21790	883	16	10	15	6	13	13	13	57	+1:16.719	5837217	44	2	00:01:37.07	1
21791	883	822	3	17	15	14	14	14	57	+1:21.511	5842009	57	9	00:01:38.192	1
21792	883	13	6	4	4	15	15	15	57	+1:26.364	5846862	42	16	00:01:38.839	1
21793	883	817	5	19	13	16	16	16	56	\N	\N	51	21	00:01:39.579	11
21794	883	819	207	20	18	17	17	17	56	\N	\N	37	20	00:01:39.546	11
21795	883	821	15	12	22	18	18	18	56	\N	\N	45	10	00:01:38.202	11
21796	883	824	206	22	19	19	19	19	56	\N	\N	50	14	00:01:38.756	11
21797	883	820	206	23	21	20	20	20	56	\N	\N	50	18	00:01:39.279	11
21798	883	823	207	21	20	21	21	21	55	\N	\N	49	19	00:01:39.334	12
21799	883	818	5	18	16	\N	R	22	16	\N	\N	4	22	00:01:43.107	29
21800	884	4	6	3	5	1	1	1	66	1:39:16.596	5956596	53	5	00:01:26.681	1
21801	884	8	208	7	4	2	2	2	66	+9.338	5965934	47	6	00:01:26.757	1
21802	884	13	6	4	9	3	3	3	66	+26.049	5982645	56	2	00:01:26.394	1
21803	884	20	9	1	3	4	4	4	66	+38.273	5994869	55	9	00:01:27.036	1
21804	884	17	9	2	7	5	5	5	66	+47.963	6004559	55	8	00:01:27.017	1
21805	884	3	131	9	1	6	6	6	66	+1:08.020	6024616	56	11	00:01:27.591	1
21806	884	814	10	14	10	7	7	7	66	+1:08.988	6025584	55	7	00:01:26.776	1
21807	884	18	1	5	14	8	8	8	66	+1:19.506	6036102	55	14	00:01:27.957	1
21808	884	815	1	6	8	9	9	9	66	+1:21.738	6038334	55	10	00:01:27.251	1
21809	884	817	5	19	11	10	10	10	65	\N	\N	55	16	00:01:28.083	11
21810	884	821	15	12	19	11	11	11	65	\N	\N	56	1	00:01:26.217	11
21811	884	1	131	10	2	12	12	12	65	\N	\N	53	13	00:01:27.895	11
21812	884	16	10	15	13	13	13	13	65	\N	\N	38	3	00:01:26.564	11
21813	884	813	3	16	17	14	14	14	65	\N	\N	56	12	00:01:27.849	11
21814	884	807	15	11	15	15	15	15	65	\N	\N	58	4	00:01:26.586	11
21815	884	822	3	17	16	16	16	16	65	\N	\N	27	20	00:01:29.747	11
21816	884	819	207	20	22	17	17	17	65	\N	\N	43	19	00:01:29.362	11
21817	884	824	206	22	20	18	18	18	64	\N	\N	55	18	00:01:28.884	12
21818	884	820	206	23	21	19	19	19	64	\N	\N	49	15	00:01:28.011	12
21819	884	818	5	18	12	20	20	20	52	\N	\N	41	17	00:01:28.231	3
21820	884	823	207	21	18	21	21	21	21	\N	\N	11	21	00:01:30.597	36
21821	884	154	208	8	6	22	22	22	8	\N	\N	5	22	00:01:31.136	22
21822	885	3	131	9	1	1	1	1	78	2:17:52.056	8272056	74	6	00:01:18.327	1
21823	885	20	9	1	3	2	2	2	78	+3.888	8275944	77	1	00:01:16.577	1
21824	885	17	9	2	4	3	3	3	78	+6.314	8278370	77	4	00:01:18.262	1
21825	885	1	131	10	2	4	4	4	78	+13.894	8285950	76	3	00:01:18.133	1
21826	885	16	10	15	8	5	5	5	78	+21.477	8293533	74	5	00:01:18.292	1
21827	885	18	1	5	9	6	6	6	78	+23.103	8295159	76	8	00:01:18.72	1
21828	885	4	6	3	6	7	7	7	78	+26.734	8298790	77	12	00:01:19.34	1
21829	885	818	5	18	10	8	8	8	78	+27.223	8299279	77	10	00:01:19.151	1
21830	885	814	10	14	17	9	9	9	78	+27.608	8299664	77	11	00:01:19.215	1
21831	885	8	208	7	5	10	10	10	78	+36.582	8308638	78	2	00:01:17.392	1
21832	885	807	15	11	11	11	11	11	78	+42.572	8314628	29	15	00:01:19.853	1
21833	885	822	3	17	14	12	12	12	78	+42.691	8314747	68	20	00:01:20.921	1
21834	885	821	15	12	19	13	13	13	78	+43.212	8315268	71	7	00:01:18.685	1
21835	885	820	206	23	22	14	14	14	78	+49.885	8321941	78	9	00:01:19.016	1
21836	885	823	207	21	15	15	15	15	78	+1:02.590	8334646	50	17	00:01:20.494	1
21837	885	815	1	6	7	16	16	16	72	\N	\N	27	14	00:01:19.53	22
21838	885	154	208	8	13	\N	R	17	63	\N	\N	57	21	00:01:20.969	4
21839	885	817	5	19	12	\N	R	18	61	\N	\N	26	13	00:01:19.426	4
21840	885	824	206	22	20	\N	R	19	58	\N	\N	49	18	00:01:20.617	23
21841	885	813	3	16	16	\N	R	20	44	\N	\N	8	19	00:01:20.881	4
21842	885	13	6	4	21	\N	R	21	28	\N	\N	28	16	00:01:20.064	3
21843	885	819	207	20	18	\N	R	22	7	\N	\N	4	22	00:01:22.772	6
21844	886	20	9	1	1	1	1	1	70	1:32:09.143	5529143	55	5	00:01:16.561	1
21845	886	4	6	3	6	2	2	2	70	+14.408	5543551	69	2	00:01:16.203	1
21846	886	1	131	10	2	3	3	3	70	+15.942	5545085	69	3	00:01:16.354	1
21847	886	17	9	2	5	4	4	4	70	+25.731	5554874	69	1	00:01:16.182	1
21848	886	3	131	9	4	5	5	5	70	+1:09.725	5598868	70	4	00:01:16.534	1
21849	886	818	5	18	7	6	6	6	69	\N	\N	61	13	00:01:17.909	11
21850	886	814	10	14	17	7	7	7	69	\N	\N	63	12	00:01:17.841	11
21851	886	13	6	4	16	8	8	8	69	\N	\N	69	6	00:01:16.939	11
21852	886	8	208	7	10	9	9	9	69	\N	\N	61	11	00:01:17.766	11
21853	886	16	10	15	8	10	10	10	69	\N	\N	68	10	00:01:17.694	11
21854	886	815	1	6	12	11	11	11	69	\N	\N	69	7	00:01:17.369	11
21855	886	18	1	5	14	12	12	12	69	\N	\N	68	8	00:01:17.458	11
21856	886	154	208	8	22	13	13	13	69	\N	\N	62	9	00:01:17.607	11
21857	886	822	3	17	3	14	14	14	69	\N	\N	63	14	00:01:18.004	11
21858	886	817	5	19	11	15	15	15	68	\N	\N	68	16	00:01:18.257	12
21859	886	813	3	16	13	16	16	16	68	\N	\N	68	15	00:01:18.105	12
21860	886	824	206	22	19	17	17	17	68	\N	\N	68	17	00:01:18.873	12
21861	886	819	207	20	18	18	18	18	67	\N	\N	60	19	00:01:19.38	13
21862	886	820	206	23	20	19	19	19	67	\N	\N	67	21	00:01:19.566	13
21863	886	821	15	12	15	20	20	20	63	\N	\N	52	20	00:01:19.478	3
21864	886	807	15	11	9	\N	R	21	45	\N	\N	40	18	00:01:19.056	4
21865	886	823	207	21	21	\N	R	22	43	\N	\N	42	22	00:01:21.811	4
21866	887	3	131	9	2	1	1	1	52	1:32:59.456	5579456	50	2	00:01:33.531	1
21867	887	17	9	2	4	2	2	2	52	+0.765	5580221	52	1	00:01:33.401	1
21868	887	4	6	3	9	3	3	3	52	+7.124	5586580	50	3	00:01:34.09	1
21869	887	1	131	10	1	4	4	4	52	+7.756	5587212	51	4	00:01:34.159	1
21870	887	8	208	7	8	5	5	5	52	+11.257	5590713	49	8	00:01:35.384	1
21871	887	13	6	4	11	6	6	6	52	+14.573	5594029	51	6	00:01:35.273	1
21872	887	16	10	15	6	7	7	7	52	+16.335	5595791	35	12	00:01:35.961	1
21873	887	817	5	19	5	8	8	8	52	+16.543	5595999	37	11	00:01:35.927	1
21874	887	814	10	14	21	9	9	9	52	+17.943	5597399	52	7	00:01:35.33	1
21875	887	807	15	11	14	10	10	10	52	+19.709	5599165	48	13	00:01:36.013	1
21876	887	813	3	16	15	11	11	11	52	+21.135	5600591	52	10	00:01:35.907	1
21877	887	822	3	17	16	12	12	12	52	+25.094	5604550	52	15	00:01:36.312	1
21878	887	18	1	5	10	13	13	13	52	+25.969	5605425	39	16	00:01:36.356	1
21879	887	821	15	12	17	14	14	14	52	+26.285	5605741	32	17	00:01:36.439	1
21880	887	819	207	20	18	15	15	15	52	+31.613	5611069	52	18	00:01:37.091	1
21881	887	824	206	22	19	16	16	16	52	+36.097	5615553	51	19	00:01:37.978	1
21882	887	820	206	23	20	17	17	17	52	+1:07.660	5647116	50	22	00:01:39.156	1
21883	887	823	207	21	22	18	18	18	52	+1:07.759	5647215	50	21	00:01:38.722	1
21884	887	154	208	8	7	19	19	19	51	\N	\N	48	9	00:01:35.614	31
21885	887	815	1	6	13	20	20	20	46	\N	\N	37	14	00:01:36.131	36
21886	887	20	9	1	3	\N	R	21	41	\N	\N	37	5	00:01:35.018	6
21887	887	818	5	18	12	\N	R	22	35	\N	\N	30	20	00:01:38.37	27
21888	888	20	9	1	2	1	1	1	60	1:41:14.711	6074711	59	5	00:01:34.164	1
21889	888	8	208	7	4	2	2	2	60	+1.008	6075719	57	2	00:01:33.767	1
21890	888	154	208	8	5	3	3	3	60	+5.830	6080541	57	10	00:01:34.576	1
21891	888	4	6	3	8	4	4	4	60	+7.721	6082432	51	1	00:01:33.468	1
21892	888	1	131	10	1	5	5	5	60	+26.927	6101638	57	4	00:01:34.156	1
21893	888	18	1	5	9	6	6	6	60	+27.996	6102707	49	7	00:01:34.201	1
21894	888	17	9	2	3	7	7	7	60	+37.562	6112273	55	11	00:01:34.782	1
21895	888	815	1	6	13	8	8	8	60	+38.306	6113017	50	15	00:01:36.134	1
21896	888	3	131	9	11	9	9	9	60	+46.821	6121532	55	6	00:01:34.181	1
21897	888	807	15	11	10	10	10	10	60	+49.892	6124603	58	8	00:01:34.244	1
21898	888	814	10	14	12	11	11	11	60	+53.771	6128482	43	16	00:01:36.566	1
21899	888	817	5	19	6	12	12	12	60	+56.975	6131686	58	14	00:01:35.982	1
21900	888	16	10	15	15	13	13	13	60	+57.738	6132449	60	13	00:01:35.816	1
21901	888	821	15	12	14	14	14	14	60	+1:00.160	6134871	56	12	00:01:35.792	1
21902	888	813	3	16	18	15	15	15	60	+1:01.929	6136640	56	9	00:01:34.293	1
21903	888	822	3	17	17	16	16	16	59	\N	\N	56	3	00:01:33.972	11
21904	888	819	207	20	22	17	17	17	59	\N	\N	51	17	00:01:37.584	11
21905	888	823	207	21	20	18	18	18	59	\N	\N	40	19	00:01:38.509	11
21906	888	820	206	23	21	19	19	19	59	\N	\N	47	18	00:01:38.383	11
21907	888	818	5	18	16	\N	R	20	22	\N	\N	12	21	00:01:39.281	9
21908	888	824	206	22	19	\N	R	21	21	\N	\N	20	22	00:01:39.844	5
21909	888	13	6	4	7	\N	R	22	3	\N	\N	3	20	00:01:38.89	20
21910	890	1	131	10	1	1	1	1	70	1:42:29.445	6149445	69	3	00:01:24.647	1
21911	890	8	208	7	6	2	2	2	70	+10.938	6160383	61	6	00:01:25.26	1
21912	890	20	9	1	2	3	3	3	70	+12.459	6161904	57	2	00:01:24.553	1
21913	890	17	9	2	10	4	4	4	70	+18.044	6167489	61	1	00:01:24.069	1
21914	890	4	6	3	5	5	5	5	70	+31.411	6180856	56	8	00:01:25.394	1
21915	890	154	208	8	3	6	6	6	70	+52.295	6201740	54	7	00:01:25.328	1
21916	890	18	1	5	13	7	7	7	70	+53.819	6203264	56	11	00:01:26.195	1
21917	890	13	6	4	7	8	8	8	70	+56.447	6205892	59	5	00:01:25.176	1
21918	890	815	1	6	9	9	9	9	69	\N	\N	59	10	00:01:26.143	11
21919	890	813	3	16	15	10	10	10	69	\N	\N	69	9	00:01:25.597	11
21920	890	807	15	11	12	11	11	11	69	\N	\N	58	14	00:01:26.74	11
21921	890	818	5	18	14	12	12	12	69	\N	\N	53	12	00:01:26.491	11
21922	890	817	5	19	8	13	13	13	69	\N	\N	58	15	00:01:26.863	11
21923	890	823	207	21	20	14	14	14	68	\N	\N	47	17	00:01:27.473	12
21924	890	819	207	20	19	15	15	15	68	\N	\N	54	18	00:01:27.725	12
21925	890	824	206	22	21	16	16	16	67	\N	\N	57	20	00:01:28.25	13
21926	890	820	206	23	22	17	17	17	67	\N	\N	65	19	00:01:28.16	13
21927	890	814	10	14	18	18	18	18	66	\N	\N	55	13	00:01:26.608	9
21928	890	3	131	9	4	19	19	19	64	\N	\N	62	4	00:01:25.089	5
21929	890	822	3	17	16	\N	R	20	42	\N	\N	41	16	00:01:27.127	9
21930	890	821	15	12	17	\N	R	21	28	\N	\N	16	22	00:01:29.135	7
21931	890	16	10	15	11	\N	R	22	19	\N	\N	12	21	00:01:28.548	9
21932	891	20	9	1	2	1	1	1	44	1:23:42.196	5022196	40	1	00:01:50.756	1
21933	891	4	6	3	9	2	2	2	44	+16.869	5039065	36	4	00:01:51.383	1
21934	891	1	131	10	1	3	3	3	44	+27.734	5049930	39	7	00:01:51.596	1
21935	891	3	131	9	4	4	4	4	44	+29.872	5052068	39	6	00:01:51.582	1
21936	891	17	9	2	3	5	5	5	44	+33.845	5056041	31	5	00:01:51.397	1
21937	891	18	1	5	6	6	6	6	44	+40.794	5062990	36	2	00:01:50.823	1
21938	891	13	6	4	10	7	7	7	44	+53.922	5076118	40	9	00:01:52.182	1
21939	891	154	208	8	7	8	8	8	44	+55.846	5078042	34	11	00:01:52.497	1
21940	891	16	10	15	12	9	9	9	44	+1:09.547	5091743	35	10	00:01:52.226	1
21941	891	817	5	19	19	10	10	10	44	+1:13.470	5095666	38	3	00:01:50.967	1
21942	891	815	1	6	13	11	11	11	44	+1:21.936	5104132	34	16	00:01:53.472	1
21943	891	818	5	18	18	12	12	12	44	+1:26.740	5108936	29	14	00:01:53.065	1
21944	891	807	15	11	11	13	13	13	44	+1:28.258	5110454	41	15	00:01:53.11	1
21945	891	821	15	12	21	14	14	14	44	+1:40.436	5122632	30	8	00:01:51.849	1
21946	891	822	3	17	20	15	15	15	44	+1:47.456	5129652	31	13	00:01:52.688	1
21947	891	823	207	21	14	16	16	16	43	\N	\N	43	18	00:01:53.995	11
21948	891	813	3	16	17	17	17	17	43	\N	\N	35	12	00:01:52.579	11
21949	891	824	206	22	15	18	18	18	43	\N	\N	37	20	00:01:54.894	11
21950	891	820	206	23	16	19	19	19	42	\N	\N	31	21	00:01:54.924	12
21951	891	814	10	14	5	\N	R	20	26	\N	\N	21	19	00:01:54.757	4
21952	891	8	208	7	8	\N	R	21	25	\N	\N	20	17	00:01:53.688	23
21953	891	819	207	20	22	\N	R	22	8	\N	\N	7	22	00:01:57.33	44
21954	892	20	9	1	1	1	1	1	53	1:18:33.352	4713352	52	12	00:01:27.19	1
21955	892	4	6	3	5	2	2	2	53	+5.467	4718819	52	5	00:01:26.797	1
21956	892	17	9	2	2	3	3	3	53	+6.350	4719702	53	3	00:01:26.69	1
21957	892	13	6	4	4	4	4	4	53	+9.361	4722713	48	10	00:01:27.095	1
21958	892	807	15	11	3	5	5	5	53	+10.355	4723707	48	4	00:01:26.716	1
21959	892	3	131	9	6	6	6	6	53	+10.999	4724351	50	2	00:01:26.5	1
21960	892	817	5	19	7	7	7	7	53	+32.329	4745681	52	13	00:01:27.294	1
21961	892	154	208	8	13	8	8	8	53	+33.130	4746482	52	8	00:01:27.043	1
21962	892	1	131	10	12	9	9	9	53	+33.527	4746879	51	1	00:01:25.849	1
21963	892	18	1	5	9	10	10	10	53	+38.327	4751679	46	16	00:01:27.83	1
21964	892	8	208	7	11	11	11	11	53	+38.695	4752047	45	6	00:01:26.948	1
21965	892	815	1	6	8	12	12	12	53	+39.765	4753117	44	15	00:01:27.607	1
21966	892	821	15	12	16	13	13	13	53	+40.880	4754232	53	9	00:01:27.092	1
21967	892	813	3	16	14	14	14	14	53	+49.085	4762437	51	7	00:01:26.981	1
21968	892	822	3	17	18	15	15	15	53	+56.827	4770179	53	11	00:01:27.166	1
21969	892	16	10	15	17	16	16	16	52	\N	\N	38	14	00:01:27.418	11
21970	892	819	207	20	20	17	17	17	52	\N	\N	52	17	00:01:28.62	11
21971	892	823	207	21	19	18	18	18	52	\N	\N	52	18	00:01:28.663	11
21972	892	824	206	22	21	19	19	19	52	\N	\N	47	20	00:01:29.595	11
21973	892	820	206	23	22	20	20	20	52	\N	\N	48	19	00:01:29.491	11
21974	892	818	5	18	10	\N	R	21	14	\N	\N	14	21	00:01:29.71	7
21975	892	814	10	14	15	\N	R	22	0	\N	\N	\N	0	\N	3
21976	893	20	9	1	1	1	1	1	61	1:59:13.132	7153132	46	1	00:01:48.574	1
21977	893	4	6	3	7	2	2	2	61	+32.627	7185759	44	11	00:01:51.082	1
21978	893	8	208	7	13	3	3	3	61	+43.920	7197052	55	13	00:01:51.14	1
21979	893	3	131	9	2	4	4	4	61	+51.155	7204287	51	6	00:01:50.353	1
21980	893	1	131	10	5	5	5	5	61	+53.159	7206291	59	4	00:01:49.916	1
21981	893	13	6	4	6	6	6	6	61	+1:03.877	7217009	45	7	00:01:50.509	1
21982	893	18	1	5	8	7	7	7	61	+1:23.354	7236486	46	15	00:01:51.74	1
21983	893	815	1	6	14	8	8	8	61	+1:23.820	7236952	46	16	00:01:51.926	1
21984	893	807	15	11	11	9	9	9	61	+1:24.261	7237393	47	18	00:01:52.186	1
21985	893	16	10	15	15	10	10	10	61	+1:24.668	7237800	43	2	00:01:49.656	1
21986	893	813	3	16	18	11	11	11	61	+1:28.479	7241611	46	8	00:01:50.708	1
21987	893	821	15	12	10	12	12	12	61	+1:37.894	7251026	37	17	00:01:52.007	1
21988	893	822	3	17	16	13	13	13	61	+1:45.161	7258293	53	14	00:01:51.706	1
21989	893	818	5	18	12	14	14	14	61	+1:53.512	7266644	45	5	00:01:50.328	1
21990	893	17	9	2	4	15	15	15	60	\N	\N	51	3	00:01:49.783	34
21991	893	823	207	21	20	16	16	16	60	\N	\N	44	19	00:01:52.472	11
21992	893	820	206	23	22	17	17	17	60	\N	\N	50	21	00:01:53.041	11
21993	893	824	206	22	21	18	18	18	60	\N	\N	45	20	00:01:52.898	11
21994	893	819	207	20	19	19	19	19	60	\N	\N	58	10	00:01:50.99	11
21995	893	814	10	14	17	20	20	20	54	\N	\N	45	9	00:01:50.739	3
21996	893	154	208	8	3	\N	R	21	37	\N	\N	35	12	00:01:51.097	63
21997	893	817	5	19	9	\N	R	22	23	\N	\N	23	22	00:01:53.052	3
21998	894	20	9	1	1	1	1	1	55	1:43:13.701	6193701	53	1	00:01:41.38	1
21999	894	8	208	7	9	2	2	2	55	+4.224	6197925	51	3	00:01:41.975	1
22000	894	154	208	8	3	3	3	3	55	+4.927	6198628	46	2	00:01:41.936	1
22001	894	807	15	11	7	4	4	4	55	+24.114	6217815	53	6	00:01:42.608	1
22002	894	1	131	10	2	5	5	5	55	+25.255	6218956	53	5	00:01:42.539	1
22003	894	4	6	3	5	6	6	6	55	+26.189	6219890	54	7	00:01:42.709	1
22004	894	3	131	9	4	7	7	7	55	+26.698	6220399	54	4	00:01:42.471	1
22005	894	18	1	5	11	8	8	8	55	+32.262	6225963	45	12	00:01:43.073	1
22006	894	13	6	4	6	9	9	9	55	+34.390	6228091	47	10	00:01:42.954	1
22007	894	815	1	6	10	10	10	10	55	+35.155	6228856	47	11	00:01:42.973	1
22008	894	821	15	12	8	11	11	11	55	+35.990	6229691	55	8	00:01:42.744	1
22009	894	822	3	17	17	12	12	12	55	+47.049	6240750	44	14	00:01:43.869	1
22010	894	813	3	16	18	13	13	13	55	+50.013	6243714	43	17	00:01:44.136	1
22011	894	819	207	20	19	14	14	14	55	+1:03.578	6257279	54	19	00:01:44.477	1
22012	894	823	207	21	20	15	15	15	55	+1:04.501	6258202	55	18	00:01:44.375	1
22013	894	824	206	22	22	16	16	16	55	+1:07.970	6261671	54	20	00:01:44.991	1
22014	894	820	206	23	21	17	17	17	55	+1:12.898	6266599	48	21	00:01:45.408	1
22015	894	818	5	18	16	18	18	18	53	\N	\N	52	15	00:01:44.09	12
22016	894	817	5	19	12	19	19	19	52	\N	\N	52	9	00:01:42.947	13
22017	894	16	10	15	14	20	20	20	50	\N	\N	43	16	00:01:44.095	4
22018	894	17	9	2	13	\N	R	21	36	\N	\N	27	13	00:01:43.863	4
22019	894	814	10	14	15	\N	R	22	24	\N	\N	10	22	00:01:46.411	20
22020	895	20	9	1	2	1	1	1	53	1:26:49.301	5209301	39	4	00:01:35.317	1
22021	895	17	9	2	1	2	2	2	53	+7.129	5216430	44	1	00:01:34.587	1
22022	895	154	208	8	4	3	3	3	53	+9.910	5219211	48	10	00:01:35.991	1
22023	895	4	6	3	8	4	4	4	53	+45.605	5254906	39	8	00:01:35.877	1
22024	895	8	208	7	9	5	5	5	53	+47.325	5256626	35	5	00:01:35.516	1
22025	895	807	15	11	7	6	6	6	53	+51.615	5260916	33	11	00:01:36.482	1
22026	895	821	15	12	14	7	7	7	53	+1:11.630	5280931	50	12	00:01:36.499	1
22027	895	3	131	9	6	8	8	8	53	+1:12.023	5281324	46	2	00:01:34.65	1
22028	895	18	1	5	10	9	9	9	53	+1:20.821	5290122	53	6	00:01:35.549	1
22029	895	13	6	4	5	10	10	10	53	+1:29.263	5298564	30	13	00:01:37.001	1
22030	895	814	10	14	12	11	11	11	53	+1:38.572	5307873	41	15	00:01:37.407	1
22031	895	818	5	18	17	12	12	12	52	\N	\N	52	9	00:01:35.895	11
22032	895	817	5	19	16	13	13	13	52	\N	\N	52	3	00:01:35.02	11
22033	895	16	10	15	22	14	14	14	52	\N	\N	29	14	00:01:37.367	11
22034	895	815	1	6	11	15	15	15	52	\N	\N	46	7	00:01:35.845	11
22035	895	813	3	16	15	16	16	16	52	\N	\N	30	16	00:01:37.423	11
22036	895	822	3	17	13	17	17	17	52	\N	\N	43	18	00:01:37.856	11
22037	895	819	207	20	20	18	18	18	52	\N	\N	51	17	00:01:37.489	11
22038	895	820	206	23	18	19	19	19	52	\N	\N	45	19	00:01:38.713	11
22039	895	1	131	10	3	\N	R	20	7	\N	\N	3	20	00:01:41.202	29
22040	895	823	207	21	19	\N	R	21	0	\N	\N	\N	0	\N	3
22041	895	824	206	22	21	\N	R	22	0	\N	\N	\N	0	\N	3
22042	896	20	9	1	1	1	1	1	60	1:31:12.187	5472187	54	2	00:01:28.116	1
22043	896	3	131	9	2	2	2	2	60	+29.823	5502010	49	9	00:01:28.816	1
22044	896	154	208	8	17	3	3	3	60	+39.892	5512079	57	7	00:01:28.796	1
22045	896	13	6	4	5	4	4	4	60	+41.692	5513879	54	11	00:01:28.886	1
22046	896	815	1	6	9	5	5	5	60	+43.829	5516016	59	4	00:01:28.503	1
22047	896	1	131	10	3	6	6	6	60	+52.475	5524662	53	15	00:01:29.052	1
22048	896	8	208	7	6	7	7	7	60	+1:07.988	5540175	60	1	00:01:27.679	1
22049	896	814	10	14	12	8	8	8	60	+1:12.868	5545055	58	17	00:01:29.3	1
22050	896	16	10	15	13	9	9	9	60	+1:14.734	5546921	60	3	00:01:28.419	1
22051	896	817	5	19	11	10	10	10	60	+1:16.237	5548424	60	10	00:01:28.831	1
22052	896	4	6	3	8	11	11	11	60	+1:18.297	5550484	58	6	00:01:28.709	1
22053	896	813	3	16	18	12	12	12	60	+1:18.951	5551138	56	14	00:01:29.012	1
22054	896	818	5	18	14	13	13	13	59	\N	\N	53	16	00:01:29.28	11
22055	896	18	1	5	10	14	14	14	59	\N	\N	57	8	00:01:28.814	11
22056	896	821	15	12	16	15	15	15	59	\N	\N	49	5	00:01:28.682	11
22057	896	822	3	17	15	16	16	16	59	\N	\N	52	12	00:01:28.928	11
22058	896	820	206	23	22	17	17	17	58	\N	\N	56	20	00:01:30.335	12
22059	896	824	206	22	19	18	18	18	58	\N	\N	57	19	00:01:30.171	12
22060	896	807	15	11	7	19	19	19	54	\N	\N	52	13	00:01:28.947	26
22061	896	17	9	2	4	\N	R	20	39	\N	\N	30	18	00:01:29.5	91
22062	896	819	207	20	21	\N	R	21	35	\N	\N	32	21	00:01:32.907	9
22063	896	823	207	21	20	\N	R	22	1	\N	\N	\N	0	\N	4
22064	897	20	9	1	2	1	1	1	55	1:38:06.106	5886106	51	2	00:01:43.893	1
22065	897	17	9	2	1	2	2	2	55	+30.829	5916935	49	5	00:01:44.364	1
22066	897	3	131	9	3	3	3	3	55	+33.650	5919756	51	6	00:01:44.458	1
22067	897	154	208	8	6	4	4	4	55	+34.802	5920908	54	3	00:01:44.301	1
22068	897	4	6	3	10	5	5	5	55	+1:07.181	5953287	55	1	00:01:43.434	1
22069	897	814	10	14	11	6	6	6	55	+1:18.174	5964280	55	14	00:01:45.786	1
22070	897	1	131	10	4	7	7	7	55	+1:19.267	5965373	47	10	00:01:45.463	1
22071	897	13	6	4	7	8	8	8	55	+1:22.886	5968992	52	9	00:01:45.447	1
22072	897	815	1	6	8	9	9	9	55	+1:31.198	5977304	51	8	00:01:45.435	1
22073	897	16	10	15	17	10	10	10	55	+1:33.257	5979363	48	13	00:01:45.609	1
22074	897	813	3	16	14	11	11	11	55	+1:35.989	5982095	55	11	00:01:45.53	1
22075	897	18	1	5	12	12	12	12	55	+1:43.767	5989873	43	17	00:01:46.336	1
22076	897	821	15	12	16	13	13	13	55	+1:44.295	5990401	43	15	00:01:45.974	1
22077	897	807	15	11	5	14	14	14	54	\N	\N	52	12	00:01:45.57	11
22078	897	822	3	17	15	15	15	15	54	\N	\N	54	4	00:01:44.351	11
22079	897	817	5	19	9	16	16	16	54	\N	\N	46	16	00:01:46.042	11
22080	897	818	5	18	13	17	17	17	54	\N	\N	53	7	00:01:44.517	11
22081	897	823	207	21	18	18	18	18	54	\N	\N	48	19	00:01:46.592	11
22082	897	819	207	20	19	19	19	19	54	\N	\N	50	18	00:01:46.432	11
22083	897	824	206	22	21	20	20	20	53	\N	\N	52	20	00:01:47.619	12
22084	897	820	206	23	20	21	21	21	53	\N	\N	52	21	00:01:47.707	12
22085	897	8	208	7	22	\N	R	22	0	\N	\N	\N	0	\N	3
22086	898	20	9	1	1	1	1	1	56	1:39:17.148	5957148	54	1	00:01:39.856	1
22087	898	154	208	8	3	2	2	2	56	+6.284	5963432	52	2	00:01:40.445	1
22088	898	17	9	2	2	3	3	3	56	+8.396	5965544	52	4	00:01:40.591	1
22089	898	1	131	10	5	4	4	4	56	+27.358	5984506	50	5	00:01:40.818	1
22090	898	4	6	3	6	5	5	5	56	+29.592	5986740	52	10	00:01:41.186	1
22091	898	807	15	11	4	6	6	6	56	+30.400	5987548	54	6	00:01:40.952	1
22092	898	815	1	6	7	7	7	7	56	+46.692	6003840	47	15	00:01:41.83	1
22093	898	822	3	17	9	8	8	8	56	+54.509	6011657	54	3	00:01:40.492	1
22094	898	3	131	9	12	9	9	9	56	+59.141	6016289	51	8	00:01:41.133	1
22095	898	18	1	5	15	10	10	10	56	+1:17.278	6034426	50	12	00:01:41.285	1
22096	898	817	5	19	10	11	11	11	56	+1:21.004	6038152	45	16	00:01:42.119	1
22097	898	818	5	18	14	12	12	12	56	+1:24.574	6041722	52	13	00:01:41.32	1
22098	898	13	6	4	13	13	13	13	56	+1:26.914	6044062	53	11	00:01:41.209	1
22099	898	821	15	12	20	14	14	14	56	+1:31.707	6048855	51	14	00:01:41.401	1
22100	898	5	208	7	8	15	15	15	56	+1:35.063	6052211	52	7	00:01:41.028	1
22101	898	814	10	14	11	16	16	16	56	+1:36.853	6054001	54	9	00:01:41.148	1
22102	898	813	3	16	17	17	17	17	55	\N	\N	42	17	00:01:43.058	11
22103	898	824	206	22	19	18	18	18	55	\N	\N	45	18	00:01:43.419	11
22104	898	823	207	21	18	19	19	19	55	\N	\N	45	20	00:01:43.933	11
22105	898	819	207	20	22	20	20	20	55	\N	\N	48	21	00:01:43.968	11
22106	898	820	206	23	21	21	21	21	54	\N	\N	48	19	00:01:43.775	12
22107	898	16	10	15	16	\N	R	22	0	\N	\N	\N	0	\N	3
22108	899	20	9	1	1	1	1	1	71	1:32:36.300	5556300	51	3	00:01:15.624	1
22109	899	17	9	2	4	2	2	2	71	+10.452	5566752	51	1	00:01:15.436	1
22110	899	4	6	3	3	3	3	3	71	+18.913	5575213	50	2	00:01:15.496	1
22111	899	18	1	5	14	4	4	4	71	+37.360	5593660	52	7	00:01:16.45	1
22112	899	3	131	9	2	5	5	5	71	+39.048	5595348	60	6	00:01:16.442	1
22113	899	815	1	6	19	6	6	6	71	+44.051	5600351	50	5	00:01:16.246	1
22114	899	13	6	4	9	7	7	7	71	+49.110	5605410	49	8	00:01:16.47	1
22115	899	807	15	11	10	8	8	8	71	+1:04.252	5620552	49	12	00:01:16.802	1
22116	899	1	131	10	5	9	9	9	71	+1:12.903	5629203	51	10	00:01:16.692	1
22117	899	817	5	19	7	10	10	10	70	\N	\N	45	15	00:01:16.974	11
22118	899	814	10	14	12	11	11	11	70	\N	\N	58	14	00:01:16.855	11
22119	899	821	15	12	17	12	12	12	70	\N	\N	59	9	00:01:16.528	11
22120	899	16	10	15	15	13	13	13	70	\N	\N	57	4	00:01:16.049	11
22121	899	5	208	7	11	14	14	14	70	\N	\N	70	16	00:01:17.249	11
22122	899	818	5	18	8	15	15	15	70	\N	\N	49	11	00:01:16.79	11
22123	899	813	3	16	16	16	16	16	70	\N	\N	45	18	00:01:17.554	11
22124	899	824	206	22	21	17	17	17	69	\N	\N	67	20	00:01:17.717	12
22125	899	823	207	21	20	18	18	18	69	\N	\N	51	19	00:01:17.59	12
22126	899	820	206	23	22	19	19	19	69	\N	\N	68	17	00:01:17.281	12
22127	899	819	207	20	18	\N	R	20	58	\N	\N	27	21	00:01:18.434	26
22128	899	822	3	17	13	\N	R	21	45	\N	\N	43	13	00:01:16.84	3
22129	899	154	208	8	6	\N	R	22	2	\N	\N	2	22	00:01:20.898	5
22130	900	3	131	6	3	1	1	1	57	1:32:58.710	5578710	19	1	00:01:32.478	1
22131	900	825	1	20	4	2	2	2	57	+26.777	5605487	49	6	00:01:33.066	1
22132	900	18	1	22	10	3	3	3	57	+30.027	5608737	39	5	00:01:32.917	1
22133	900	4	6	14	5	4	4	4	57	+35.284	5613994	57	7	00:01:33.186	1
22134	900	822	3	77	15	5	5	5	57	+47.639	5626349	56	3	00:01:32.616	1
22135	900	807	10	27	7	6	6	6	57	+50.718	5629428	56	2	00:01:32.568	1
22136	900	8	6	7	11	7	7	7	57	+57.675	5636385	56	8	00:01:33.21	1
22137	900	818	5	25	6	8	8	8	57	+1:00.441	5639151	56	10	00:01:33.691	1
22138	900	826	5	26	8	9	9	9	57	+1:03.585	5642295	35	11	00:01:33.864	1
22139	900	815	10	11	16	10	10	10	57	+1:25.916	5664626	38	4	00:01:32.634	1
22140	900	16	15	99	13	11	11	11	56	\N	\N	34	9	00:01:33.366	11
22141	900	821	15	21	20	12	12	12	56	\N	\N	41	13	00:01:34.564	11
22142	900	820	206	4	17	13	13	13	55	\N	\N	33	12	00:01:34.202	12
22143	900	824	206	17	18	\N	N	14	49	\N	\N	55	16	00:01:35.635	18
22144	900	154	208	8	22	\N	R	15	43	\N	\N	41	15	00:01:35.281	132
22145	900	813	208	13	21	\N	R	16	29	\N	\N	30	14	00:01:34.766	132
22146	900	828	207	9	19	\N	R	17	27	\N	\N	17	18	00:01:37.332	51
22147	900	20	9	1	12	\N	R	18	3	\N	\N	26	17	00:01:37.064	5
22148	900	1	131	44	1	\N	R	19	2	\N	\N	2	20	00:01:49.947	5
22149	900	13	3	19	9	\N	R	20	0	\N	\N	2	19	00:01:40.287	4
22150	900	155	207	10	14	\N	R	21	0	\N	\N	\N	0	\N	4
22151	900	817	9	3	2	\N	D	22	57	+24.525	5603235	\N	0	\N	2
22152	901	1	131	44	1	1	1	1	56	1:40:25.974	6025974	53	1	00:01:43.066	1
22153	901	3	131	6	3	2	2	2	56	+17.313	6043287	55	2	00:01:43.96	1
22154	901	20	9	1	2	3	3	3	56	+24.534	6050508	51	4	00:01:44.289	1
22155	901	4	6	14	4	4	4	4	56	+35.992	6061966	47	3	00:01:44.165	1
22156	901	807	10	27	7	5	5	5	56	+47.199	6073173	38	10	00:01:45.982	1
22157	901	18	1	22	10	6	6	6	56	+1:23.691	6109665	47	11	00:01:46.039	1
22158	901	13	3	19	13	7	7	7	56	+1:25.076	6111050	44	6	00:01:44.897	1
22159	901	822	3	77	18	8	8	8	56	+1:25.537	6111511	31	9	00:01:45.475	1
22160	901	825	1	20	8	9	9	9	55	\N	\N	44	8	00:01:45.373	11
22161	901	826	5	26	11	10	10	10	55	\N	\N	36	13	00:01:46.695	11
22162	901	154	208	8	15	11	11	11	55	\N	\N	42	12	00:01:46.224	11
22163	901	8	6	7	6	12	12	12	55	\N	\N	36	7	00:01:45.129	11
22164	901	155	207	10	20	13	13	13	55	\N	\N	53	15	00:01:47.753	11
22165	901	828	207	9	22	14	14	14	54	\N	\N	40	14	00:01:47.5	12
22166	901	820	206	4	21	15	15	15	54	\N	\N	49	18	00:01:48.249	12
22167	901	817	9	3	5	\N	R	16	49	\N	\N	48	5	00:01:44.675	39
22168	901	821	15	21	12	\N	R	17	35	\N	\N	27	16	00:01:47.782	6
22169	901	16	15	99	17	\N	R	18	32	\N	\N	27	17	00:01:48.04	10
22170	901	818	5	25	9	\N	R	19	18	\N	\N	4	19	00:01:48.527	131
22171	901	824	206	17	19	\N	R	20	8	\N	\N	4	21	00:01:51.473	23
22172	901	813	208	13	16	\N	R	21	7	\N	\N	6	20	00:01:50.929	5
22173	901	815	10	11	14	\N	W	22	0	\N	\N	\N	0	\N	54
22174	902	1	131	44	2	1	1	1	57	1:39:42.743	5982743	49	2	00:01:37.108	1
22175	902	3	131	6	1	2	2	2	57	+1.085	5983828	49	1	00:01:37.02	1
22176	902	815	10	11	4	3	3	3	57	+24.067	6006810	36	7	00:01:39.32	1
22177	902	817	9	3	13	4	4	4	57	+24.489	6007232	38	4	00:01:39.269	1
22178	902	807	10	27	11	5	5	5	57	+28.654	6011397	37	3	00:01:38.785	1
22179	902	20	9	1	10	6	6	6	57	+29.879	6012622	18	6	00:01:39.312	1
22180	902	13	3	19	7	7	7	7	57	+31.265	6014008	40	5	00:01:39.272	1
22181	902	822	3	77	3	8	8	8	57	+31.876	6014619	50	13	00:01:39.762	1
22182	902	4	6	14	9	9	9	9	57	+32.595	6015338	53	12	00:01:39.732	1
22183	902	8	6	7	5	10	10	10	57	+33.462	6016205	35	8	00:01:39.438	1
22184	902	826	5	26	12	11	11	11	57	+41.342	6024085	12	15	00:01:40.16	1
22185	902	154	208	8	16	12	12	12	57	+43.143	6025886	39	9	00:01:39.443	1
22186	902	820	206	4	21	13	13	13	57	+59.909	6042652	48	21	00:01:41.825	1
22187	902	813	208	13	17	14	14	14	57	+1:02.803	6045546	52	11	00:01:39.666	1
22188	902	155	207	10	18	15	15	15	57	+1:27.900	6070643	17	18	00:01:41.246	1
22189	902	824	206	17	19	16	16	16	56	\N	\N	44	22	00:01:42.175	11
22190	902	18	1	22	6	17	17	17	55	\N	\N	37	10	00:01:39.565	8
22191	902	825	1	20	8	\N	R	18	40	\N	\N	40	14	00:01:40.108	8
22192	902	821	15	21	15	\N	R	19	39	\N	\N	32	16	00:01:40.698	4
22193	902	828	207	9	20	\N	R	20	33	\N	\N	28	17	00:01:41.134	31
22194	902	818	5	25	14	\N	R	21	18	\N	\N	16	19	00:01:41.65	31
22195	902	16	15	99	22	\N	R	22	17	\N	\N	9	20	00:01:41.791	4
22196	903	1	131	44	1	1	1	1	54	1:33:28.338	5608338	42	2	00:01:41.196	1
22197	903	3	131	6	4	2	2	2	54	+18.062	5626400	39	1	00:01:40.402	1
22198	903	4	6	14	5	3	3	3	54	+23.604	5631942	48	4	00:01:42.081	1
22199	903	817	9	3	2	4	4	4	54	+27.136	5635474	39	3	00:01:41.473	1
22200	903	20	9	1	3	5	5	5	54	+47.778	5656116	37	5	00:01:42.169	1
22201	903	807	10	27	8	6	6	6	54	+54.295	5662633	33	10	00:01:42.624	1
22202	903	822	3	77	7	7	7	7	54	+55.697	5664035	52	11	00:01:42.66	1
22203	903	8	6	7	11	8	8	8	54	+1:16.335	5684673	34	8	00:01:42.3	1
22204	903	815	10	11	16	9	9	9	54	+1:22.647	5690985	32	6	00:01:42.228	1
22205	903	826	5	26	13	10	10	10	53	\N	\N	33	17	00:01:43.337	11
22206	903	18	1	22	12	11	11	11	53	\N	\N	30	18	00:01:43.375	11
22207	903	818	5	25	9	12	12	12	53	\N	\N	34	14	00:01:42.896	11
22208	903	825	1	20	15	13	13	13	53	\N	\N	33	12	00:01:42.701	11
22209	903	813	208	13	22	14	14	14	53	\N	\N	34	15	00:01:43.067	11
22210	903	13	3	19	6	15	15	15	53	\N	\N	34	9	00:01:42.379	11
22211	903	821	15	21	17	16	16	16	53	\N	\N	42	7	00:01:42.257	11
22212	903	824	206	17	19	17	17	17	53	\N	\N	36	21	00:01:44.825	11
22213	903	155	207	10	18	18	18	18	53	\N	\N	48	16	00:01:43.323	11
22214	903	820	206	4	21	19	19	19	52	\N	\N	50	13	00:01:42.875	12
22215	903	828	207	9	20	20	20	20	52	\N	\N	30	19	00:01:43.62	12
22216	903	154	208	8	10	\N	R	21	28	\N	\N	4	20	00:01:44.366	6
22217	903	16	15	99	14	\N	R	22	5	\N	\N	2	22	00:01:58.376	5
22218	904	1	131	44	1	1	1	1	66	1:41:05.155	6065155	54	3	00:01:29.483	1
22219	904	3	131	6	2	2	2	2	66	+0.636	6065791	51	2	00:01:29.236	1
22220	904	817	9	3	3	3	3	3	66	+49.014	6114169	65	5	00:01:30.012	1
22221	904	20	9	1	15	4	4	4	66	+1:16.702	6141857	55	1	00:01:28.918	1
22222	904	822	3	77	4	5	5	5	66	+1:19.293	6144448	47	8	00:01:30.424	1
22223	904	4	6	14	7	6	6	6	66	+1:27.743	6152898	55	4	00:01:29.898	1
22224	904	8	6	7	6	7	7	7	65	\N	\N	53	11	00:01:30.58	11
22225	904	154	208	8	5	8	8	8	65	\N	\N	47	14	00:01:31.068	11
22226	904	815	10	11	11	9	9	9	65	\N	\N	39	13	00:01:30.756	11
22227	904	807	10	27	10	10	10	10	65	\N	\N	42	16	00:01:31.411	11
22228	904	18	1	22	8	11	11	11	65	\N	\N	43	10	00:01:30.563	11
22229	904	825	1	20	14	12	12	12	65	\N	\N	43	7	00:01:30.318	11
22230	904	13	3	19	9	13	13	13	65	\N	\N	55	9	00:01:30.468	11
22231	904	826	5	26	12	14	14	14	65	\N	\N	59	6	00:01:30.269	11
22232	904	813	208	13	22	15	15	15	65	\N	\N	39	15	00:01:31.235	11
22233	904	821	15	21	13	16	16	16	65	\N	\N	55	12	00:01:30.666	11
22234	904	16	15	99	16	17	17	17	65	\N	\N	38	17	00:01:31.473	11
22235	904	824	206	17	18	18	18	18	64	\N	\N	46	20	00:01:31.784	12
22236	904	820	206	4	17	19	19	19	64	\N	\N	44	18	00:01:31.767	12
22237	904	828	207	9	19	20	20	20	64	\N	\N	54	22	00:01:33.35	12
22238	904	155	207	10	20	\N	R	21	34	\N	\N	25	21	00:01:33.064	23
22239	904	818	5	25	21	\N	R	22	24	\N	\N	18	19	00:01:31.781	43
22240	905	3	131	6	1	1	1	1	78	1:49:27.661	6567661	33	4	00:01:19.425	1
22241	905	1	131	44	2	2	2	2	78	+9.210	6576871	34	3	00:01:19.361	1
22242	905	817	9	3	3	3	3	3	78	+9.614	6577275	70	2	00:01:19.252	1
22243	905	4	6	14	5	4	4	4	78	+32.452	6600113	54	5	00:01:19.727	1
22244	905	807	10	27	11	5	5	5	77	\N	\N	38	9	00:01:20.767	11
22245	905	18	1	22	12	6	6	6	77	\N	\N	42	12	00:01:21.047	11
22246	905	13	3	19	16	7	7	7	77	\N	\N	48	6	00:01:20.314	11
22247	905	154	208	8	14	8	8	8	77	\N	\N	53	11	00:01:20.979	11
22248	905	824	206	17	21	9	9	9	77	\N	\N	42	16	00:01:21.254	11
22249	905	825	1	20	8	10	10	10	77	\N	\N	75	8	00:01:20.657	11
22250	905	828	207	9	22	11	11	11	77	\N	\N	53	10	00:01:20.911	11
22251	905	8	6	7	6	12	12	12	77	\N	\N	75	1	00:01:18.479	11
22252	905	155	207	10	20	13	13	13	75	\N	\N	16	19	00:01:22.425	12
22253	905	820	206	4	19	14	14	14	75	\N	\N	69	7	00:01:20.579	13
22254	905	821	15	21	17	\N	R	15	59	\N	\N	41	15	00:01:21.146	3
22255	905	822	3	77	13	\N	R	16	55	\N	\N	50	14	00:01:21.105	5
22256	905	818	5	25	7	\N	R	17	50	\N	\N	35	13	00:01:21.083	5
22257	905	16	15	99	18	\N	R	18	23	\N	\N	23	17	00:01:21.761	3
22258	905	826	5	26	9	\N	R	19	10	\N	\N	8	18	00:01:22.011	26
22259	905	20	9	1	4	\N	R	20	5	\N	\N	3	20	00:01:59.505	101
22260	905	815	10	11	10	\N	R	21	0	\N	\N	\N	0	\N	4
22261	905	813	208	13	15	\N	W	22	0	\N	\N	\N	0	\N	54
22262	906	817	9	3	6	1	1	1	70	1:39:12.830	5952830	68	4	00:01:18.64	1
22263	906	3	131	6	1	2	2	2	70	+4.236	5957066	33	7	00:01:18.881	1
22264	906	20	9	1	3	3	3	3	70	+5.247	5958077	48	10	00:01:19.171	1
22265	906	18	1	22	9	4	4	4	70	+11.755	5964585	64	5	00:01:18.759	1
22266	906	807	10	27	11	5	5	5	70	+12.843	5965673	64	8	00:01:18.936	1
22267	906	4	6	14	7	6	6	6	70	+14.869	5967699	64	3	00:01:18.614	1
22268	906	822	3	77	4	7	7	7	70	+23.578	5976408	52	11	00:01:19.321	1
22269	906	818	5	25	8	8	8	8	70	+28.026	5980856	56	12	00:01:19.399	1
22270	906	825	1	20	12	9	9	9	70	+29.254	5982084	56	6	00:01:18.819	1
22271	906	8	6	7	10	10	10	10	70	+53.678	6006508	68	2	00:01:18.529	1
22272	906	815	10	11	13	11	11	11	69	\N	\N	63	13	00:01:19.491	4
22273	906	13	3	19	5	12	12	12	69	\N	\N	58	1	00:01:18.504	4
22274	906	16	15	99	16	13	13	13	69	\N	\N	66	17	00:01:20.226	11
22275	906	821	15	21	22	14	14	14	64	\N	\N	51	16	00:01:20.112	132
22276	906	154	208	8	14	\N	R	15	59	\N	\N	54	14	00:01:19.65	65
22277	906	826	5	26	15	\N	R	16	47	\N	\N	43	15	00:01:19.978	79
22278	906	1	131	44	2	\N	R	17	46	\N	\N	24	9	00:01:18.942	23
22279	906	155	207	10	21	\N	R	18	23	\N	\N	20	19	00:01:23.13	22
22280	906	813	208	13	17	\N	R	19	21	\N	\N	21	18	00:01:21.514	131
22281	906	828	207	9	20	\N	R	20	7	\N	\N	7	20	00:01:51.041	101
22282	906	820	206	4	18	\N	R	21	0	\N	\N	\N	0	\N	4
22283	906	824	206	17	19	\N	R	22	0	\N	\N	\N	0	\N	4
22284	907	3	131	6	3	1	1	1	71	1:27:54.976	5274976	50	6	00:01:12.598	1
22285	907	1	131	44	9	2	2	2	71	+1.932	5276908	41	2	00:01:12.217	1
22286	907	822	3	77	2	3	3	3	71	+8.172	5283148	63	3	00:01:12.581	1
22287	907	13	3	19	1	4	4	4	71	+17.358	5292334	63	4	00:01:12.586	1
22288	907	4	6	14	4	5	5	5	71	+18.553	5293529	58	5	00:01:12.595	1
22289	907	815	10	11	15	6	6	6	71	+28.546	5303522	59	1	00:01:12.142	1
22290	907	825	1	20	6	7	7	7	71	+32.031	5307007	53	7	00:01:12.746	1
22291	907	817	9	3	5	8	8	8	71	+43.522	5318498	55	10	00:01:13.06	1
22292	907	807	10	27	10	9	9	9	71	+44.137	5319113	60	11	00:01:13.156	1
22293	907	8	6	7	8	10	10	10	71	+47.777	5322753	55	9	00:01:12.884	1
22294	907	18	1	22	11	11	11	11	71	+50.966	5325942	60	8	00:01:12.858	1
22295	907	813	208	13	13	12	12	12	70	\N	\N	64	12	00:01:13.187	11
22296	907	16	15	99	16	13	13	13	70	\N	\N	59	14	00:01:13.709	11
22297	907	154	208	8	22	14	14	14	70	\N	\N	42	15	00:01:13.953	11
22298	907	824	206	17	18	15	15	15	69	\N	\N	65	19	00:01:14.476	12
22299	907	155	207	10	19	16	16	16	69	\N	\N	40	22	00:01:15.274	12
22300	907	820	206	4	21	17	17	17	69	\N	\N	40	21	00:01:14.847	12
22301	907	828	207	9	20	18	18	18	69	\N	\N	33	20	00:01:14.672	12
22302	907	821	15	21	17	19	19	19	69	\N	\N	53	16	00:01:14.036	12
22303	907	818	5	25	14	\N	R	20	59	\N	\N	55	13	00:01:13.317	23
22304	907	20	9	1	12	\N	R	21	34	\N	\N	30	17	00:01:14.254	10
22305	907	826	5	26	7	\N	R	22	24	\N	\N	23	18	00:01:14.332	22
22306	908	1	131	44	6	1	1	1	52	2:26:52.094	8812094	26	1	00:01:37.176	1
22307	908	822	3	77	14	2	2	2	52	+30.135	8842229	34	4	00:01:38.264	1
22308	908	817	9	3	8	3	3	3	52	+46.495	8858589	34	7	00:01:38.459	1
22309	908	18	1	22	3	4	4	4	52	+47.390	8859484	52	5	00:01:38.284	1
22310	908	20	9	1	2	5	5	5	52	+53.864	8865958	52	2	00:01:37.481	1
22311	908	4	6	14	16	6	6	6	52	+59.946	8872040	52	8	00:01:38.587	1
22312	908	825	1	20	5	7	7	7	52	+1:02.563	8874657	32	10	00:01:38.677	1
22313	908	807	10	27	4	8	8	8	52	+1:28.692	8900786	52	9	00:01:38.625	1
22314	908	826	5	26	9	9	9	9	52	+1:29.340	8901434	45	6	00:01:38.407	1
22315	908	818	5	25	10	10	10	10	51	\N	\N	44	13	00:01:39.261	11
22316	908	815	10	11	7	11	11	11	51	\N	\N	41	11	00:01:38.716	11
22317	908	154	208	8	11	12	12	12	51	\N	\N	48	12	00:01:38.919	11
22318	908	16	15	99	13	13	13	13	51	\N	\N	34	15	00:01:40.041	11
22319	908	824	206	17	12	14	14	14	51	\N	\N	51	14	00:01:39.961	11
22320	908	155	207	10	22	15	15	15	50	\N	\N	31	18	00:01:41.462	12
22321	908	820	206	4	17	16	16	16	50	\N	\N	50	17	00:01:40.399	12
22322	908	813	208	13	20	17	17	17	49	\N	\N	48	16	00:01:40.314	13
22323	908	3	131	6	1	\N	R	18	28	\N	\N	26	3	00:01:38.091	6
22324	908	828	207	9	21	\N	R	19	11	\N	\N	7	20	00:01:44.319	22
22325	908	821	15	21	19	\N	R	20	9	\N	\N	7	19	00:01:42.566	4
22326	908	13	3	19	15	\N	R	21	0	\N	\N	\N	0	\N	4
22327	908	8	6	7	18	\N	R	22	0	\N	\N	\N	0	\N	4
22328	909	3	131	6	1	1	1	1	67	1:33:42.914	5622914	67	6	00:01:21.298	1
22329	909	822	3	77	2	2	2	2	67	+20.789	5643703	45	9	00:01:21.494	1
22330	909	1	131	44	20	3	3	3	67	+22.530	5645444	53	1	00:01:19.908	1
22331	909	20	9	1	6	4	4	4	67	+44.014	5666928	39	10	00:01:21.545	1
22332	909	4	6	14	7	5	5	5	67	+52.467	5675381	57	3	00:01:20.548	1
22333	909	817	9	3	5	6	6	6	67	+52.549	5675463	53	5	00:01:20.846	1
22334	909	807	10	27	9	7	7	7	67	+1:04.178	5687092	44	13	00:01:22.098	1
22335	909	18	1	22	11	8	8	8	67	+1:24.711	5707625	64	8	00:01:21.346	1
22336	909	825	1	20	4	9	9	9	66	\N	\N	56	2	00:01:20.224	11
22337	909	815	10	11	10	10	10	10	66	\N	\N	54	4	00:01:20.752	11
22338	909	8	6	7	12	11	11	11	66	\N	\N	55	7	00:01:21.338	11
22339	909	813	208	13	18	12	12	12	66	\N	\N	41	15	00:01:22.305	11
22340	909	818	5	25	13	13	13	13	66	\N	\N	58	11	00:01:21.876	11
22341	909	821	15	21	16	14	14	14	66	\N	\N	61	12	00:01:22.008	11
22342	909	824	206	17	17	15	15	15	66	\N	\N	57	16	00:01:22.522	11
22343	909	155	207	10	19	16	16	16	65	\N	\N	50	18	00:01:22.866	12
22344	909	820	206	4	21	17	17	17	65	\N	\N	50	19	00:01:23.035	12
22345	909	828	207	9	22	18	18	18	65	\N	\N	49	20	00:01:23.23	12
22346	909	16	15	99	15	\N	R	19	47	\N	\N	41	17	00:01:22.529	23
22347	909	826	5	26	8	\N	R	20	44	\N	\N	34	14	00:01:22.179	44
22348	909	154	208	8	14	\N	R	21	26	\N	\N	26	21	00:01:24.137	47
22349	909	13	3	19	3	\N	R	22	0	\N	\N	\N	0	\N	4
22350	910	817	9	3	4	1	1	1	70	1:53:05.058	6785058	58	2	00:01:26.608	1
22351	910	4	6	14	5	2	2	2	70	+5.225	6790283	40	5	00:01:27.419	1
22352	910	1	131	44	22	3	3	3	70	+5.857	6790915	36	4	00:01:27.38	1
22353	910	3	131	6	1	4	4	4	70	+6.361s	6791419	64	1	00:01:25.724	1
22354	910	13	3	19	6	5	5	5	70	+29.841	6814899	51	7	00:01:28.229	1
22355	910	8	6	7	16	6	6	6	70	+31.491	6816549	47	6	00:01:27.983	1
22356	910	20	9	1	2	7	7	7	70	+40.964	6826022	52	9	00:01:28.746	1
22357	910	822	3	77	3	8	8	8	70	+41.344	6826402	63	3	00:01:26.85	1
22358	910	818	5	25	8	9	9	9	70	+58.527	6843585	31	11	00:01:29.12	1
22359	910	18	1	22	7	10	10	10	70	+1:07.280	6852338	50	13	00:01:29.156	1
22360	910	16	15	99	11	11	11	11	70	+1:08.169	6853227	41	8	00:01:28.704	1
22361	910	825	1	20	21	12	12	12	70	+1:18.465	6863523	41	10	00:01:28.883	1
22362	910	813	208	13	20	13	13	13	70	+1:24.024	6869082	45	12	00:01:29.128	1
22363	910	826	5	26	10	14	14	14	69	\N	\N	51	14	00:01:29.401	11
22364	910	824	206	17	15	15	15	15	69	\N	\N	49	16	00:01:29.883	11
22365	910	820	206	4	18	16	16	16	69	\N	\N	47	15	00:01:29.499	11
22366	910	821	15	21	13	\N	R	17	33	\N	\N	29	18	00:01:30.485	31
22367	910	155	207	10	17	\N	R	18	26	\N	\N	21	19	00:01:32.888	31
22368	910	815	10	11	12	\N	R	19	23	\N	\N	21	17	00:01:30.28	3
22369	910	807	10	27	9	\N	R	20	16	\N	\N	14	20	00:01:41.151	3
22370	910	154	208	8	14	\N	R	21	11	\N	\N	7	21	00:01:46.312	3
22371	910	828	207	9	19	\N	R	22	8	\N	\N	6	22	00:01:48.459	3
22373	911	817	9	3	5	1	1	1	44	1:24:36.556	5076556	44	6	00:01:52.974	1
22374	911	3	131	6	1	2	2	2	44	+3.383	5079939	36	1	00:01:50.511	1
22375	911	822	3	77	6	3	3	3	44	+28.032	5104588	40	4	00:01:52.716	1
22376	911	8	6	7	8	4	4	4	44	+36.815	5113371	39	13	00:01:54.09	1
22377	911	20	9	1	3	5	5	5	44	+52.196	5128752	36	5	00:01:52.953	1
22378	911	18	1	22	10	6	6	6	44	+54.580	5131136	38	8	00:01:53.483	1
22379	911	4	6	14	4	7	7	7	44	+1:01.162	5137718	29	11	00:01:53.879	1
22380	911	815	10	11	13	8	8	8	44	+1:04.293	5140849	28	16	00:01:54.532	1
22381	911	826	5	26	11	9	9	9	44	+1:05.347	5141903	26	14	00:01:54.159	1
22382	911	807	10	27	18	10	10	10	44	+1:05.697	5142253	40	9	00:01:53.612	1
22383	911	818	5	25	12	11	11	11	44	+1:11.920	5148476	31	7	00:01:53.276	1
22384	911	825	1	20	7	12	12	12	44	+1:14.262	5150818	28	15	00:01:54.203	1
22385	911	13	3	19	9	13	13	13	44	+1:15.975	5152531	37	3	00:01:52.512	1
22386	911	16	15	99	14	14	14	14	44	+1:22.447	5159003	36	2	00:01:52.413	1
22387	911	821	15	21	20	15	15	15	44	+1:30.825	5167381	32	12	00:01:54	1
22388	911	820	206	4	19	16	16	16	43	\N	\N	31	17	00:01:55.247	11
22389	911	828	207	9	22	17	17	17	43	\N	\N	26	19	00:01:55.9	11
22390	911	824	206	17	16	18	18	18	39	\N	\N	32	20	00:01:56.347	6
22391	911	1	131	44	2	\N	R	19	38	\N	\N	33	10	00:01:53.707	31
22392	911	154	208	8	15	\N	R	20	33	\N	\N	21	18	00:01:55.649	31
22393	911	813	208	13	17	\N	R	21	1	\N	\N	\N	0	\N	26
22394	911	827	207	45	21	\N	R	22	1	\N	\N	\N	0	\N	131
22395	912	1	131	44	1	1	1	1	53	1:19:10.236	4750236	29	1	00:01:28.004	1
22396	912	3	131	6	2	2	2	2	53	+3.175	4753411	51	2	00:01:28.206	1
22397	912	13	3	19	4	3	3	3	53	+25.026	4775262	46	3	00:01:28.342	1
22398	912	822	3	77	3	4	4	4	53	+40.786	4791022	50	5	00:01:28.559	1
22399	912	817	9	3	9	5	5	5	53	+50.309	4800545	53	6	00:01:28.588	1
22400	912	20	9	1	8	6	6	6	53	+59.965	4810201	34	10	00:01:29.141	1
22401	912	815	10	11	10	7	7	7	53	+1:02.518	4812754	35	8	00:01:29.107	1
22402	912	18	1	22	6	8	8	8	53	+1:03.063	4813299	35	11	00:01:29.245	1
22403	912	8	6	7	11	9	9	9	53	+1:03.535	4813771	43	7	00:01:28.942	1
22404	912	825	1	20	5	10	10	10	53	+1:06.171	4816407	34	12	00:01:29.283	1
22405	912	826	5	26	21	11	11	11	53	+1:11.184	4821420	51	4	00:01:28.486	1
22406	912	807	10	27	13	12	12	12	53	+1:12.606	4822842	35	13	00:01:29.366	1
22407	912	818	5	25	12	13	13	13	53	+1:13.093	4823329	39	9	00:01:29.121	1
22408	912	813	208	13	16	14	14	14	52	\N	\N	32	17	00:01:29.856	11
22409	912	16	15	99	14	15	15	15	52	\N	\N	46	14	00:01:29.375	11
22410	912	154	208	8	17	16	16	16	52	\N	\N	38	18	00:01:30.083	11
22411	912	155	207	10	18	17	17	17	52	\N	\N	35	21	00:01:30.758	11
22412	912	824	206	17	19	18	18	18	52	\N	\N	51	20	00:01:30.521	11
22413	912	821	15	21	15	19	19	19	51	\N	\N	40	15	00:01:29.449	12
22414	912	828	207	9	22	20	20	20	51	\N	\N	47	19	00:01:30.28	12
22415	912	4	6	14	7	\N	R	21	28	\N	\N	23	16	00:01:29.68	5
22416	912	820	206	4	20	\N	R	22	5	\N	\N	5	22	00:01:32.569	3
22417	913	1	131	44	1	1	1	1	60	2:00:04.795	7204795	39	1	00:01:50.417	1
22418	913	20	9	1	4	2	2	2	60	+13.534	7218329	27	8	00:01:52.519	1
22419	913	817	9	3	3	3	3	3	60	+14.273	7219068	30	9	00:01:52.569	1
22420	913	4	6	14	5	4	4	4	60	+15.389	7220184	27	6	00:01:52.115	1
22421	913	13	3	19	6	5	5	5	60	+42.161	7246956	27	13	00:01:53.283	1
22422	913	818	5	25	12	6	6	6	60	+56.801	7261596	48	4	00:01:51.937	1
22423	913	815	10	11	15	7	7	7	60	+59.038	7263833	46	5	00:01:52.007	1
22424	913	8	6	7	7	8	8	8	60	+1:00.641	7265436	28	11	00:01:52.872	1
22425	913	807	10	27	13	9	9	9	60	+1:01.661	7266456	27	10	00:01:52.762	1
22426	913	825	1	20	9	10	10	10	60	+1:02.230	7267025	48	2	00:01:51.639	1
22427	913	822	3	77	8	11	11	11	60	+1:05.065	7269860	25	7	00:01:52.515	1
22428	913	813	208	13	18	12	12	12	60	+1:06.915	7271710	26	12	00:01:53.213	1
22429	913	154	208	8	16	13	13	13	60	+1:08.029	7272824	25	15	00:01:53.543	1
22430	913	826	5	26	10	14	14	14	60	+1:12.008	7276803	45	3	00:01:51.761	1
22431	913	828	207	9	22	15	15	15	60	+1:34.188	7298983	14	19	00:01:55.416	1
22432	913	824	206	17	19	16	16	16	60	+1:34.543	7299338	47	14	00:01:53.538	1
22433	913	820	206	4	21	17	17	17	59	\N	\N	43	17	00:01:53.807	11
22434	913	18	1	22	11	\N	R	18	52	\N	\N	16	16	00:01:53.707	31
22435	913	16	15	99	17	\N	R	19	40	\N	\N	10	18	00:01:53.948	34
22436	913	821	15	21	14	\N	R	20	17	\N	\N	6	20	00:01:55.684	10
22437	913	3	131	6	2	\N	R	21	13	\N	\N	5	21	00:01:56.769	10
22438	913	155	207	10	20	\N	W	22	0	\N	\N	\N	0	\N	131
22439	914	1	131	44	2	1	1	1	44	1:51:43.021	6703021	39	1	00:01:51.6	1
22440	914	3	131	6	1	2	2	2	44	+9.180	6712201	15	6	00:01:52.551	1
22441	914	20	9	1	9	3	3	3	44	+29.122	6732143	32	3	00:01:51.915	1
22442	914	817	9	3	6	4	4	4	44	+38.818	6741839	38	4	00:01:52.231	1
22443	914	18	1	22	8	5	5	5	44	+1:07.550	6770571	33	2	00:01:51.721	1
22444	914	822	3	77	3	6	6	6	44	+1:53.773	6816794	41	13	00:01:54.103	1
22445	914	13	3	19	4	7	7	7	44	+1:55.126	6818147	39	8	00:01:53.45	1
22446	914	807	10	27	13	8	8	8	44	+1:55.948	6818969	28	7	00:01:52.814	1
22447	914	818	5	25	20	9	9	9	44	+2:07.638	6830659	35	11	00:01:53.562	1
22448	914	815	10	11	11	10	10	10	43	\N	\N	27	10	00:01:53.556	11
22449	914	826	5	26	12	11	11	11	43	\N	\N	25	12	00:01:54.021	11
22450	914	8	6	7	10	12	12	12	43	\N	\N	36	5	00:01:52.426	11
22451	914	821	15	21	15	13	13	13	43	\N	\N	40	17	00:01:55.372	11
22452	914	825	1	20	7	14	14	14	43	\N	\N	38	9	00:01:53.51	11
22453	914	154	208	8	16	15	15	15	43	\N	\N	28	16	00:01:55.302	11
22454	914	813	208	13	22	16	16	16	43	\N	\N	26	15	00:01:54.702	11
22455	914	828	207	9	17	17	17	17	43	\N	\N	27	14	00:01:54.669	11
22456	914	820	206	4	21	18	18	18	43	\N	\N	25	21	00:01:56.472	11
22457	914	155	207	10	19	19	19	19	43	\N	\N	29	18	00:01:55.641	11
22458	914	824	206	17	18	20	20	20	41	\N	\N	27	20	00:01:55.985	3
22459	914	16	15	99	14	21	21	21	40	\N	\N	25	19	00:01:55.753	3
22460	914	4	6	14	5	\N	R	22	2	\N	\N	\N	0	\N	40
22461	915	1	131	44	1	1	1	1	53	1:31:50.744	5510744	48	3	00:01:41.606	1
22462	915	3	131	6	2	2	2	2	53	+13.657	5524401	52	2	00:01:41.36	1
22463	915	822	3	77	3	3	3	3	53	+17.425	5528169	53	1	00:01:40.896	1
22464	915	18	1	22	4	4	4	4	53	+30.234	5540978	47	4	00:01:41.964	1
22465	915	825	1	20	11	5	5	5	53	+53.616	5564360	44	14	00:01:43.076	1
22466	915	4	6	14	7	6	6	6	53	+1:00.016	5570760	53	6	00:01:42.179	1
22467	915	817	9	3	6	7	7	7	53	+1:01.812	5572556	50	13	00:01:43.05	1
22468	915	20	9	1	10	8	8	8	53	+1:06.185	5576929	53	8	00:01:42.63	1
22469	915	8	6	7	8	9	9	9	53	+1:18.877	5589621	45	11	00:01:42.919	1
22470	915	815	10	11	12	10	10	10	53	+1:20.067	5590811	47	12	00:01:42.924	1
22471	915	13	3	19	18	11	11	11	53	+1:20.877	5591621	47	10	00:01:42.879	1
22472	915	807	10	27	17	12	12	12	53	+1:21.309	5592053	50	9	00:01:42.685	1
22473	915	818	5	25	9	13	13	13	53	+1:37.295	5608039	53	7	00:01:42.55	1
22474	915	826	5	26	5	14	14	14	52	\N	\N	52	5	00:01:42.022	11
22475	915	821	15	21	13	15	15	15	52	\N	\N	45	18	00:01:44.075	11
22476	915	16	15	99	14	16	16	16	52	\N	\N	42	15	00:01:43.822	11
22477	915	154	208	8	15	17	17	17	52	\N	\N	49	19	00:01:44.461	11
22478	915	813	208	13	21	18	18	18	52	\N	\N	50	17	00:01:44.03	11
22479	915	828	207	9	16	19	19	19	51	\N	\N	48	16	00:01:43.979	12
22480	915	155	207	10	19	\N	R	20	21	\N	\N	17	20	00:01:47.407	23
22481	915	820	206	4	20	\N	R	21	9	\N	\N	8	21	00:01:48.268	22
22482	916	1	131	44	2	1	1	1	56	1:40:04.785	6004785	49	4	00:01:41.929	1
22483	916	3	131	6	1	2	2	2	56	+4.314	6009099	48	5	00:01:41.932	1
22484	916	817	9	3	5	3	3	3	56	+25.560	6030345	33	7	00:01:42.831	1
22485	916	13	3	19	4	4	4	4	56	+26.924	6031709	50	9	00:01:42.971	1
22486	916	822	3	77	3	5	5	5	56	+30.992	6035777	55	6	00:01:42.505	1
22487	916	4	6	14	6	6	6	6	56	+1:35.231	6100016	47	2	00:01:41.474	1
22488	916	20	9	1	18	7	7	7	56	+1:35.734	6100519	50	1	00:01:41.379	1
22489	916	825	1	20	7	8	8	8	56	+1:40.682	6105467	29	14	00:01:44.287	1
22490	916	818	5	25	14	10	10	10	56	+1:48.863	6113648	17	12	00:01:44.18	1
22491	916	813	208	13	10	9	9	9	56	+1:47.870	6112655	38	11	00:01:43.808	1
22492	916	154	208	8	16	11	11	11	55	\N	\N	51	15	00:01:44.44	11
22493	916	18	1	22	12	12	12	12	55	\N	\N	33	13	00:01:44.255	11
22494	916	8	6	7	8	13	13	13	55	\N	\N	54	8	00:01:42.888	11
22495	916	821	15	21	15	14	14	14	55	\N	\N	47	10	00:01:43.006	11
22496	916	826	5	26	17	15	15	15	55	\N	\N	53	3	00:01:41.689	11
22497	916	807	10	27	13	\N	R	16	16	\N	\N	15	16	00:01:46.226	5
22498	916	815	10	11	11	\N	R	17	1	\N	\N	\N	0	\N	130
22499	916	16	15	99	9	\N	R	18	0	\N	\N	\N	0	\N	4
22500	917	3	131	6	1	1	1	1	71	1:30:02.555	5402555	62	2	00:01:13.619	1
22501	917	1	131	44	2	2	2	2	71	+1.457	5404012	62	1	00:01:13.555	1
22502	917	13	3	19	3	3	3	3	71	+41.031	5443586	59	7	00:01:14.101	1
22503	917	18	1	22	5	4	4	4	71	+48.658	5451213	68	4	00:01:13.999	1
22504	917	20	9	1	6	5	5	5	71	+51.420	5453975	68	5	00:01:14.018	1
22505	917	4	6	14	8	6	6	6	71	+1:01.906	5464461	55	10	00:01:14.313	1
22506	917	8	6	7	10	7	7	7	71	+1:03.730	5466285	37	17	00:01:14.963	1
22507	917	807	10	27	12	8	8	8	71	+1:03.934	5466489	70	3	00:01:13.728	1
22508	917	825	1	20	7	9	9	9	71	+1:10.085	5472640	62	11	00:01:14.544	1
22509	917	822	3	77	4	10	10	10	70	\N	\N	64	9	00:01:14.229	11
22510	917	826	5	26	17	11	11	11	70	\N	\N	62	8	00:01:14.144	11
22511	917	813	208	13	16	12	12	12	70	\N	\N	47	14	00:01:14.81	11
22512	917	818	5	25	15	13	13	13	70	\N	\N	65	13	00:01:14.774	11
22513	917	821	15	21	11	14	14	14	70	\N	\N	64	16	00:01:14.875	11
22514	917	815	10	11	18	15	15	15	70	\N	\N	70	12	00:01:14.55	11
22515	917	16	15	99	13	16	16	16	70	\N	\N	42	15	00:01:14.834	11
22516	917	154	208	8	14	17	17	17	63	\N	\N	63	6	00:01:14.07	18
22517	917	817	9	3	9	\N	R	18	39	\N	\N	30	18	00:01:15.387	22
22518	918	1	131	44	2	1	1	1	55	1:39:02.619	5942619	49	4	00:01:45.599	1
22519	918	13	3	19	4	2	2	2	55	+2.576	5945195	47	2	00:01:44.826	1
22520	918	822	3	77	3	3	3	3	55	+28.880	5971499	54	6	00:01:45.727	1
22521	918	817	9	3	20	4	4	4	55	+37.237	5979856	50	1	00:01:44.496	1
22522	918	18	1	22	6	5	5	5	55	+1:00.334	6002953	47	9	00:01:46.739	1
22523	918	807	10	27	12	6	6	6	55	+1:02.148	6004767	47	7	00:01:45.777	1
22524	918	815	10	11	11	7	7	7	55	+1:11.060	6013679	49	8	00:01:45.808	1
22525	918	20	9	1	19	8	8	8	55	+1:12.045	6014664	51	3	00:01:45.552	1
22526	918	4	6	14	8	9	9	9	55	+1:25.813	6028432	45	12	00:01:47.424	1
22527	918	8	6	7	7	10	10	10	55	+1:27.820	6030439	46	16	00:01:47.736	1
22528	918	825	1	20	9	11	11	11	55	+1:30.376	6032995	37	10	00:01:46.824	1
22529	918	818	5	25	10	12	12	12	55	+1:31.947	6034566	50	5	00:01:45.686	1
22530	918	154	208	8	18	13	13	13	54	\N	\N	35	17	00:01:47.897	11
22531	918	3	131	6	1	14	14	14	54	\N	\N	17	11	00:01:46.869	11
22532	918	821	15	21	14	15	15	15	54	\N	\N	43	15	00:01:47.698	11
22533	918	16	15	99	13	16	16	16	54	\N	\N	44	14	00:01:47.508	11
22534	918	829	207	46	17	17	17	17	54	\N	\N	47	18	00:01:48.398	11
22535	918	155	207	10	16	\N	R	18	42	\N	\N	38	13	00:01:47.431	31
22536	918	813	208	13	15	\N	R	19	26	\N	\N	9	20	00:01:48.933	131
22537	918	826	5	26	5	\N	R	20	14	\N	\N	10	19	00:01:48.748	131
22538	926	1	131	44	1	1	1	1	58	1:31:54.067	5514067	50	1	00:01:30.945	1
22539	926	3	131	6	2	2	2	2	58	+1.360	5515427	47	2	00:01:31.092	1
22540	926	20	6	5	4	3	3	3	58	+34.523	5548590	52	4	00:01:31.457	1
22541	926	13	3	19	3	4	4	4	58	+38.196	5552263	50	6	00:01:31.719	1
22542	926	831	15	12	10	5	5	5	58	+1:35.149	5609216	46	9	00:01:32.612	1
22543	926	817	9	3	6	6	6	6	57	\N	\N	46	10	00:01:32.797	11
22544	926	807	10	27	13	7	7	7	57	\N	\N	48	8	00:01:31.97	11
22545	926	828	15	9	15	8	8	8	57	\N	\N	51	5	00:01:31.56	11
22546	926	832	5	55	7	9	9	9	57	\N	\N	49	11	00:01:32.872	11
22547	926	815	10	11	14	10	10	10	57	\N	\N	46	7	00:01:31.959	11
22548	926	18	1	22	16	11	11	11	56	\N	\N	56	12	00:01:33.338	12
22549	926	8	6	7	5	\N	R	12	40	\N	\N	36	3	00:01:31.426	36
22550	926	830	5	33	11	\N	R	13	32	\N	\N	30	13	00:01:34.295	5
22551	926	154	208	8	8	\N	R	14	0	\N	\N	\N	0	\N	75
22552	926	813	208	13	9	\N	R	15	0	\N	\N	\N	0	\N	3
22553	926	826	9	26	12	\N	W	16	0	\N	\N	\N	0	\N	54
22554	926	825	1	20	17	\N	W	17	0	\N	\N	\N	0	\N	54
22555	926	822	3	77	0	\N	W	18	0	\N	\N	\N	0	\N	54
22556	927	20	6	5	2	1	1	1	56	1:41:05.793	6065793	46	3	00:01:43.648	1
22557	927	1	131	44	1	2	2	2	56	+8.569	6074362	45	2	00:01:43.125	1
22558	927	3	131	6	3	3	3	3	56	+12.310	6078103	43	1	00:01:42.062	1
22559	927	8	6	7	11	4	4	4	56	+53.822	6119615	40	7	00:01:44.124	1
22560	927	822	3	77	8	5	5	5	56	+1:10.409	6136202	42	6	00:01:44.088	1
22561	927	13	3	19	7	6	6	6	56	+1:13.586	6139379	40	5	00:01:43.99	1
22562	927	830	5	33	6	7	7	7	56	+1:37.762	6163555	42	9	00:01:44.579	1
22563	927	832	5	55	15	8	8	8	55	\N	\N	37	15	00:01:45.507	11
22564	927	826	9	26	5	9	9	9	55	\N	\N	41	8	00:01:44.514	11
22565	927	817	9	3	4	10	10	10	55	\N	\N	42	13	00:01:45.312	11
22566	927	154	208	8	10	11	11	11	55	\N	\N	36	10	00:01:44.812	11
22567	927	831	15	12	16	12	12	12	55	\N	\N	45	4	00:01:43.902	11
22568	927	815	10	11	14	13	13	13	55	\N	\N	37	14	00:01:45.345	11
22569	927	807	10	27	13	14	14	14	55	\N	\N	46	11	00:01:44.822	11
22570	927	833	209	98	19	15	15	15	53	\N	\N	44	19	00:01:49.04	13
22571	927	813	208	13	12	\N	R	16	47	\N	\N	38	12	00:01:45.07	31
22572	927	18	1	22	17	\N	R	17	41	\N	\N	38	16	00:01:46.056	101
22573	927	4	1	14	18	\N	R	18	21	\N	\N	17	17	00:01:48.46	132
22574	927	828	15	9	9	\N	R	19	3	\N	\N	3	18	00:01:48.76	20
22575	927	829	209	28	0	\N	W	20	0	\N	\N	\N	0	\N	69
22576	928	1	131	44	1	1	1	1	56	1:39:42.008	5982008	31	1	00:01:42.208	1
22577	928	3	131	6	2	2	2	2	56	+0.714	5982722	39	2	00:01:42.565	1
22578	928	20	6	5	3	3	3	3	56	+2.988	5984996	15	5	00:01:43.018	1
22579	928	8	6	7	6	4	4	4	56	+3.835	5985843	48	6	00:01:43.026	1
22580	928	13	3	19	4	5	5	5	56	+8.544	5990552	37	4	00:01:42.734	1
22581	928	822	3	77	5	6	6	6	56	+9.885	5991893	37	7	00:01:43.051	1
22582	928	154	208	8	8	7	7	7	56	+19.008	6001016	34	8	00:01:43.134	1
22583	928	831	15	12	9	8	8	8	56	+22.625	6004633	46	12	00:01:43.692	1
22584	928	817	9	3	7	9	9	9	56	+32.117	6014125	46	9	00:01:43.245	1
22585	928	828	15	9	10	10	10	10	55	\N	\N	32	15	00:01:44.204	11
22586	928	815	10	11	15	11	11	11	55	\N	\N	44	10	00:01:43.512	11
22587	928	4	1	14	18	12	12	12	55	\N	\N	40	13	00:01:43.728	11
22588	928	832	5	55	14	13	13	13	55	\N	\N	41	3	00:01:42.652	11
22589	928	18	1	22	17	14	14	14	55	\N	\N	21	16	00:01:44.991	11
22590	928	829	209	28	19	15	15	15	54	\N	\N	40	17	00:01:45.414	12
22591	928	833	209	98	20	16	16	16	54	\N	\N	43	19	00:01:45.963	12
22592	928	830	5	33	13	17	17	17	52	\N	\N	46	14	00:01:43.88	7
22593	928	813	208	13	11	\N	R	18	49	\N	\N	37	11	00:01:43.686	23
22594	928	826	9	26	12	\N	R	19	15	\N	\N	13	20	00:01:46.291	131
22595	928	807	10	27	16	\N	R	20	9	\N	\N	6	18	00:01:45.844	6
22596	929	1	131	44	1	1	1	1	57	1:35:05.809	5705809	38	5	00:01:37.857	1
22597	929	8	6	7	4	2	2	2	57	+3.380	5709189	42	1	00:01:36.311	1
22598	929	3	131	6	3	3	3	3	57	+6.033	5711842	36	3	00:01:37.326	1
22599	929	822	3	77	5	4	4	4	57	+42.957	5748766	16	6	00:01:38.095	1
22600	929	20	6	5	2	5	5	5	57	+43.989	5749798	38	2	00:01:36.624	1
22601	929	817	9	3	7	6	6	6	57	+1:01.751	5767560	53	12	00:01:38.948	1
22602	929	154	208	8	10	7	7	7	57	+1:24.763	5790572	34	15	00:01:39.161	1
22603	929	815	10	11	11	8	8	8	56	\N	\N	39	8	00:01:38.338	11
22604	929	826	9	26	17	9	9	9	56	\N	\N	36	11	00:01:38.725	11
22605	929	13	3	19	6	10	10	10	56	\N	\N	12	14	00:01:39.094	11
22606	929	4	1	14	14	11	11	11	56	\N	\N	38	13	00:01:38.992	11
22607	929	831	15	12	12	12	12	12	56	\N	\N	43	7	00:01:38.216	11
22608	929	807	10	27	8	13	13	13	56	\N	\N	40	10	00:01:38.653	11
22609	929	828	15	9	13	14	14	14	56	\N	\N	27	9	00:01:38.422	11
22610	929	813	208	13	16	15	15	15	56	\N	\N	43	4	00:01:37.665	11
22611	929	829	209	28	18	16	16	16	55	\N	\N	36	18	00:01:41.759	12
22612	929	833	209	98	19	17	17	17	54	\N	\N	36	19	00:01:42.033	13
22613	929	830	5	33	15	\N	R	18	34	\N	\N	32	16	00:01:39.607	10
22614	929	832	5	55	9	\N	R	19	29	\N	\N	13	17	00:01:40.651	5
22615	929	18	1	22	20	\N	W	20	0	\N	\N	\N	0	\N	132
22616	930	3	131	6	1	1	1	1	66	1:41:12.555	6072555	53	2	00:01:29.109	1
22617	930	1	131	44	2	2	2	2	66	+17.551	6090106	54	1	00:01:28.27	1
22618	930	20	6	5	3	3	3	3	66	+45.342	6117897	61	6	00:01:30.737	1
22619	930	822	3	77	4	4	4	4	66	+59.217	6131772	44	5	00:01:30.711	1
22620	930	8	6	7	7	5	5	5	66	+1:00.002	6132557	47	3	00:01:29.931	1
22621	930	13	3	19	9	6	6	6	66	+1:21.314	6153869	51	4	00:01:30.374	1
22622	930	817	9	3	10	7	7	7	65	\N	\N	56	8	00:01:31.124	11
22623	930	154	208	8	11	8	8	8	65	\N	\N	46	15	00:01:31.945	11
22624	930	832	5	55	5	9	9	9	65	\N	\N	62	9	00:01:31.156	11
22625	930	826	9	26	8	10	10	10	65	\N	\N	40	11	00:01:31.887	11
22626	930	830	5	33	6	11	11	11	65	\N	\N	46	12	00:01:31.896	11
22627	930	831	15	12	15	12	12	12	65	\N	\N	41	13	00:01:31.928	11
22628	930	815	10	11	18	13	13	13	65	\N	\N	38	14	00:01:31.932	11
22629	930	828	15	9	16	14	14	14	65	\N	\N	52	16	00:01:32.222	11
22630	930	807	10	27	17	15	15	15	65	\N	\N	51	7	00:01:30.888	11
22631	930	18	1	22	14	16	16	16	65	\N	\N	46	10	00:01:31.162	11
22632	930	829	209	28	19	17	17	17	63	\N	\N	49	19	00:01:33.655	13
22633	930	833	209	98	20	18	18	18	62	\N	\N	51	20	00:01:34.211	14
22634	930	813	208	13	12	\N	R	19	45	\N	\N	17	17	00:01:32.912	3
22635	930	4	1	14	13	\N	R	20	26	\N	\N	23	18	00:01:33.387	23
22636	931	3	131	6	2	1	1	1	78	1:49:18.420	6558420	76	2	00:01:18.599	1
22637	931	20	6	5	3	2	2	2	78	+4.486	6562906	75	4	00:01:18.854	1
22638	931	1	131	44	1	3	3	3	78	+6.053	6564473	42	3	00:01:18.676	1
22639	931	826	9	26	5	4	4	4	78	+11.965	6570385	75	7	00:01:19.13	1
22640	931	817	9	3	4	5	5	5	78	+13.608	6572028	74	1	00:01:18.063	1
22641	931	8	6	7	6	6	6	6	78	+14.345	6572765	74	10	00:01:19.651	1
22642	931	815	10	11	7	7	7	7	78	+15.013	6573433	74	11	00:01:19.657	1
22643	931	18	1	22	10	8	8	8	78	+16.063	6574483	76	9	00:01:19.49	1
22644	931	831	15	12	14	9	9	9	78	+23.626	6582046	76	15	00:01:20.017	1
22645	931	832	5	55	0	10	10	10	78	+25.056	6583476	48	13	00:01:19.816	1
22646	931	807	10	27	11	11	11	11	78	+26.232	6584652	46	14	00:01:19.921	1
22647	931	154	208	8	15	12	12	12	78	+28.415	6586835	40	17	00:01:20.483	1
22648	931	828	15	9	17	13	13	13	78	+31.159	6589579	75	8	00:01:19.285	1
22649	931	822	3	77	16	14	14	14	78	+45.789	6604209	74	6	00:01:18.944	1
22650	931	13	3	19	12	15	15	15	77	\N	\N	72	12	00:01:19.764	11
22651	931	833	209	98	19	16	16	16	76	\N	\N	47	18	00:01:21.715	12
22652	931	829	209	28	18	17	17	17	76	\N	\N	58	20	00:01:22.693	12
22653	931	830	5	33	9	\N	R	18	62	\N	\N	49	5	00:01:18.873	3
22654	931	4	1	14	13	\N	R	19	41	\N	\N	36	16	00:01:20.459	6
22655	931	813	208	13	8	\N	R	20	5	\N	\N	3	19	00:01:22.271	23
22656	932	1	131	44	1	1	1	1	70	1:31:53.145	5513145	64	3	00:01:17.472	1
22657	932	3	131	6	2	2	2	2	70	+2.285	5515430	63	5	00:01:17.637	1
22658	932	822	3	77	4	3	3	3	70	+40.666	5553811	67	6	00:01:17.922	1
22659	932	8	6	7	3	4	4	4	70	+45.625	5558770	42	1	00:01:16.987	1
22660	932	20	6	5	18	5	5	5	70	+49.903	5563048	59	2	00:01:17.105	1
22661	932	13	3	19	15	6	6	6	70	+56.381	5569526	64	4	00:01:17.553	1
22662	932	813	208	13	6	7	7	7	70	+1:06.664	5579809	51	10	00:01:18.385	1
22663	932	807	10	27	7	8	8	8	69	\N	\N	66	9	00:01:18.238	11
22664	932	826	9	26	8	9	9	9	69	\N	\N	69	8	00:01:18.048	11
22665	932	154	208	8	5	10	10	10	69	\N	\N	51	7	00:01:17.969	11
22666	932	815	10	11	10	11	11	11	69	\N	\N	49	14	00:01:18.889	11
22667	932	832	5	55	11	12	12	12	69	\N	\N	61	12	00:01:18.811	11
22668	932	817	9	3	9	13	13	13	69	\N	\N	67	16	00:01:19.06	11
22669	932	828	15	9	12	14	14	14	69	\N	\N	58	15	00:01:18.89	11
22670	932	830	5	33	19	15	15	15	69	\N	\N	50	11	00:01:18.616	11
22671	932	831	15	12	14	16	16	16	68	\N	\N	47	17	00:01:19.088	12
22672	932	829	209	28	17	17	17	17	66	\N	\N	38	19	00:01:20.707	14
22673	932	833	209	98	16	\N	R	18	57	\N	\N	37	20	00:01:20.804	31
22674	932	18	1	22	20	\N	R	19	54	\N	\N	49	13	00:01:18.856	31
22675	932	4	1	14	13	\N	R	20	44	\N	\N	41	18	00:01:19.58	5
22676	933	3	131	6	2	1	1	1	71	1:30:16.930	5416930	35	1	00:01:11.235	1
22677	933	1	131	44	1	2	2	2	71	+8.800	5425730	60	2	00:01:11.475	1
22678	933	13	3	19	4	3	3	3	71	+17.573	5434503	58	4	00:01:11.613	1
22679	933	20	6	5	3	4	4	4	71	+18.181	5435111	44	3	00:01:11.499	1
22680	933	822	3	77	6	5	5	5	71	+53.604	5470534	52	7	00:01:12.248	1
22681	933	807	10	27	5	6	6	6	71	+1:04.075	5481005	62	12	00:01:12.541	1
22682	933	813	208	13	10	7	7	7	70	\N	\N	58	6	00:01:11.785	11
22683	933	830	5	33	7	8	8	8	70	\N	\N	64	9	00:01:12.349	11
22684	933	815	10	11	13	9	9	9	70	\N	\N	58	10	00:01:12.377	11
22685	933	817	9	3	18	10	10	10	70	\N	\N	69	5	00:01:11.689	11
22686	933	831	15	12	8	11	11	11	70	\N	\N	57	14	00:01:13.05	11
22687	933	826	9	26	15	12	12	12	70	\N	\N	54	8	00:01:12.316	11
22688	933	828	15	9	11	13	13	13	69	\N	\N	56	11	00:01:12.516	12
22689	933	833	209	98	16	14	14	14	68	\N	\N	58	16	00:01:14.939	13
22690	933	154	208	8	9	\N	R	15	35	\N	\N	34	13	00:01:12.881	6
22691	933	832	5	55	12	\N	R	16	35	\N	\N	28	15	00:01:13.234	75
22692	933	18	1	22	20	\N	R	17	8	\N	\N	5	17	00:01:52.208	31
22693	933	829	209	28	17	\N	R	18	1	\N	\N	\N	0	\N	44
22694	933	8	6	7	14	\N	R	19	0	\N	\N	\N	0	\N	4
22695	933	4	1	14	19	\N	R	20	0	\N	\N	\N	0	\N	4
22696	934	1	131	44	1	1	1	1	52	1:31:27.729	5487729	29	1	00:01:37.093	1
22697	934	3	131	6	2	2	2	2	52	+10.956	5498685	24	2	00:01:37.403	1
22698	934	20	6	5	6	3	3	3	52	+25.443	5513172	31	6	00:01:37.707	1
22699	934	13	3	19	3	4	4	4	52	+36.839	5524568	26	3	00:01:37.466	1
22700	934	822	3	77	4	5	5	5	52	+1:03.194	5550923	32	5	00:01:37.513	1
22701	934	826	9	26	7	6	6	6	52	+1:03.955	5551684	28	7	00:01:37.91	1
22702	934	807	10	27	9	7	7	7	52	+1:18.744	5566473	32	9	00:01:38.296	1
22703	934	8	6	7	5	8	8	8	51	\N	\N	31	4	00:01:37.493	11
22704	934	815	10	11	11	9	9	9	51	\N	\N	25	10	00:01:38.466	11
22705	934	4	1	14	17	10	10	10	51	\N	\N	30	12	00:01:38.883	11
22706	934	828	15	9	15	11	11	11	51	\N	\N	31	8	00:01:38.131	11
22707	934	833	209	98	20	12	12	12	49	\N	\N	26	15	00:01:42.324	13
22708	934	829	209	28	19	13	13	13	49	\N	\N	28	14	00:01:41.919	13
22709	934	832	5	55	8	\N	R	14	31	\N	\N	26	11	00:01:38.697	10
22710	934	817	9	3	10	\N	R	15	21	\N	\N	14	13	00:01:39.94	10
22711	934	830	5	33	13	\N	R	16	3	\N	\N	3	16	00:02:20.776	20
22712	934	813	208	13	14	\N	R	18	0	\N	\N	\N	0	\N	4
22713	934	18	1	22	18	\N	R	19	0	\N	\N	\N	0	\N	4
22714	934	154	208	8	12	\N	R	17	0	\N	\N	\N	0	\N	4
22715	934	831	15	12	16	\N	W	20	0	\N	\N	\N	0	\N	6
22716	936	20	6	5	3	1	1	1	69	1:46:09.985	6369985	63	5	00:01:26.772	1
22717	936	826	9	26	7	2	2	2	69	+15.748	6385733	57	4	00:01:26.519	1
22718	936	817	9	3	4	3	3	3	69	+25.084	6395069	68	1	00:01:24.821	1
22719	936	830	5	33	9	4	4	4	69	+44.251	6414236	62	11	00:01:27.65	1
22720	936	4	1	14	15	5	5	5	69	+49.079	6419064	67	10	00:01:27.311	1
22721	936	1	131	44	1	6	6	6	69	+52.025	6422010	68	3	00:01:25.727	1
22722	936	154	208	8	10	7	7	7	69	+58.578	6428563	60	14	00:01:28.08	1
22723	936	3	131	6	2	8	8	8	69	+58.876	6428861	68	2	00:01:25.149	1
22724	936	18	1	22	16	9	9	9	69	+1:07.028	6437013	65	17	00:01:28.535	1
22725	936	828	15	9	17	10	10	10	69	+1:09.130	6439115	60	12	00:01:28.004	1
22726	936	831	15	12	18	11	11	11	69	+1:13.458	6443443	51	15	00:01:28.268	1
22727	936	13	3	19	8	12	12	12	69	+1:14.278	6444263	59	6	00:01:26.864	1
22728	936	822	3	77	6	13	13	13	69	+1:20.228	6450213	51	8	00:01:27.058	1
22729	936	813	208	13	14	14	14	14	69	+1:25.142	6455127	62	9	00:01:27.13	1
22730	936	833	209	98	19	15	15	15	67	\N	\N	59	20	00:01:29.868	12
22731	936	829	209	28	20	16	16	16	65	\N	\N	56	19	00:01:29.543	14
22732	936	832	5	55	12	\N	R	17	60	\N	\N	38	18	00:01:28.611	10
22733	936	8	6	7	5	\N	R	18	55	\N	\N	24	7	00:01:26.954	131
22734	936	815	10	11	13	\N	R	19	53	\N	\N	51	16	00:01:28.499	22
22735	936	807	10	27	11	\N	R	20	41	\N	\N	38	13	00:01:28.074	33
22736	937	1	131	44	1	1	1	1	43	1:23:40.387	5020387	34	2	00:01:52.504	1
22737	937	3	131	6	2	2	2	2	43	+2.058	5022445	34	1	00:01:52.416	1
22738	937	154	208	8	9	3	3	3	43	+37.988	5058375	37	12	00:01:54.779	1
22739	937	826	9	26	12	4	4	4	43	+45.692	5066079	29	3	00:01:53.032	1
22740	937	815	10	11	4	5	5	5	43	+53.997	5074384	29	13	00:01:54.796	1
22741	937	13	3	19	6	6	6	6	43	+55.283	5075670	23	8	00:01:54.093	1
22742	937	8	6	7	16	7	7	7	43	+55.703	5076090	30	9	00:01:54.517	1
22743	937	830	5	33	18	8	8	8	43	+56.076	5076463	36	4	00:01:53.276	1
22744	937	822	3	77	3	9	9	9	43	+1:01.040	5081427	23	10	00:01:54.646	131
22745	937	828	15	9	13	10	10	10	43	+1:31.234	5111621	30	7	00:01:54.022	1
22746	937	831	15	12	14	11	11	11	43	+1:42.311	5122698	29	6	00:01:53.991	1
22747	937	20	6	5	8	12	12	12	42	\N	\N	29	14	00:01:55.316	27
22748	937	4	1	14	20	13	13	13	42	\N	\N	34	5	00:01:53.692	11
22749	937	18	1	22	19	14	14	14	42	\N	\N	38	15	00:01:55.533	11
22750	937	833	209	98	17	15	15	15	42	\N	\N	32	18	00:01:58.174	11
22751	937	829	209	28	15	16	16	16	42	\N	\N	33	17	00:01:58.15	11
22752	937	832	5	55	10	\N	R	17	32	\N	\N	25	11	00:01:54.68	131
22753	937	817	9	3	5	\N	R	18	19	\N	\N	2	16	00:01:56.263	131
22754	937	813	208	13	7	\N	R	19	2	\N	\N	\N	0	\N	5
22755	937	807	10	27	11	\N	W	20	0	\N	\N	\N	0	\N	75
22756	938	1	131	44	1	1	1	1	53	1:18:00.688	4680688	48	1	00:01:26.672	1
22757	938	20	6	5	3	2	2	2	53	+25.042	4705730	52	3	00:01:27.376	1
22758	938	13	3	19	5	3	3	3	53	+47.635	4728323	31	8	00:01:27.874	1
22759	938	822	3	77	6	4	4	4	53	+47.996	4728684	49	6	00:01:27.525	1
22760	938	8	6	7	2	5	5	5	53	+1:08.860	4749548	43	7	00:01:27.584	1
22761	938	815	10	11	7	6	6	6	53	+1:12.783	4753471	46	10	00:01:28.14	1
22762	938	807	10	27	9	7	7	7	52	\N	\N	36	14	00:01:28.913	11
22763	938	817	9	3	19	8	8	8	52	\N	\N	50	9	00:01:28.065	11
22764	938	828	15	9	12	9	9	9	52	\N	\N	22	12	00:01:28.516	11
22765	938	826	9	26	18	10	10	10	52	\N	\N	39	11	00:01:28.231	11
22766	938	832	5	55	17	11	11	11	52	\N	\N	38	5	00:01:27.51	11
22767	938	830	5	33	20	12	12	12	52	\N	\N	35	4	00:01:27.39	11
22768	938	831	15	12	17	13	13	13	52	\N	\N	51	13	00:01:28.653	11
22769	938	18	1	22	15	14	14	14	52	\N	\N	33	16	00:01:29.766	11
22770	938	829	209	28	13	15	15	15	51	\N	\N	51	17	00:01:31.098	12
22771	938	833	209	98	14	16	16	16	51	\N	\N	29	18	00:01:31.311	12
22772	938	3	131	6	4	17	17	17	50	\N	\N	43	2	00:01:27.067	13
22773	938	4	1	14	16	18	18	18	47	\N	\N	42	15	00:01:29.285	16
22774	938	154	208	8	8	\N	R	19	1	\N	\N	\N	0	\N	130
22775	938	813	208	13	10	\N	R	20	1	\N	\N	\N	0	\N	130
22776	939	20	6	5	1	1	1	1	61	2:01:22.118	7282118	53	2	00:01:50.069	1
22777	939	817	9	3	2	2	2	2	61	+1.478	7283596	52	1	00:01:50.041	1
22778	939	8	6	7	3	3	3	3	61	+17.154	7299272	48	5	00:01:50.341	1
22779	939	3	131	6	6	4	4	4	61	+24.720	7306838	50	7	00:01:50.934	1
22780	939	822	3	77	7	5	5	5	61	+34.204	7316322	49	10	00:01:51.342	1
22781	939	826	9	26	4	6	6	6	61	+35.508	7317626	36	8	00:01:51.109	1
22782	939	815	10	11	13	7	7	7	61	+50.836	7332954	44	12	00:01:51.97	1
22783	939	830	5	33	8	8	8	8	61	+51.450	7333568	43	4	00:01:50.298	1
22784	939	832	5	55	14	9	9	9	61	+52.860	7334978	43	6	00:01:50.401	1
22785	939	831	15	12	16	10	10	10	61	+1:30.045	7372163	36	15	00:01:52.566	1
22786	939	828	15	9	17	11	11	11	61	+1:37.507	7379625	30	11	00:01:51.594	1
22787	939	813	208	13	18	12	12	12	61	+1:37.718	7379836	57	3	00:01:50.175	1
22788	939	154	208	8	10	13	13	13	59	\N	\N	28	13	00:01:52.353	27
22789	939	834	209	53	20	14	14	14	59	\N	\N	43	19	00:01:55.312	12
22790	939	829	209	28	19	15	15	15	59	\N	\N	45	20	00:01:55.89	12
22791	939	18	1	22	15	\N	R	16	52	\N	\N	43	9	00:01:51.167	6
22792	939	4	1	14	12	\N	R	17	33	\N	\N	27	16	00:01:53.325	6
22793	939	1	131	44	5	\N	R	18	32	\N	\N	24	14	00:01:52.505	37
22794	939	13	3	19	9	\N	R	19	30	\N	\N	19	17	00:01:53.666	6
22795	939	807	10	27	11	\N	R	20	12	\N	\N	6	18	00:01:53.868	4
22796	940	1	131	44	2	1	1	1	53	1:28:06.508	5286508	33	1	00:01:36.145	1
22797	940	3	131	6	1	2	2	2	53	+18.964	5305472	31	2	00:01:37.147	1
22798	940	20	6	5	4	3	3	3	53	+20.850	5307358	32	3	00:01:37.906	1
22799	940	8	6	7	6	4	4	4	53	+33.768	5320276	32	4	00:01:38.035	1
22800	940	822	3	77	3	5	5	5	53	+36.746	5323254	41	8	00:01:38.241	1
22801	940	807	10	27	13	6	6	6	53	+55.559	5342067	43	9	00:01:38.331	1
22802	940	154	208	8	8	7	7	7	53	+1:12.298	5358806	35	6	00:01:38.167	1
22803	940	813	208	13	11	8	8	8	53	+1:13.575	5360083	39	5	00:01:38.136	1
22804	940	830	5	33	17	9	9	9	53	+1:35.315	5381823	32	7	00:01:38.237	1
22805	940	832	5	55	10	10	10	10	52	\N	\N	16	13	00:01:38.686	11
22806	940	4	1	14	12	11	11	11	52	\N	\N	45	16	00:01:39.614	11
22807	940	815	10	11	9	12	12	12	52	\N	\N	50	11	00:01:38.591	11
22808	940	826	9	26	20	13	13	13	52	\N	\N	36	10	00:01:38.366	11
22809	940	828	15	9	15	14	14	14	52	\N	\N	28	15	00:01:39.343	11
22810	940	817	9	3	7	15	15	15	52	\N	\N	32	14	00:01:38.898	11
22811	940	18	1	22	14	16	16	16	52	\N	\N	31	18	00:01:40.121	11
22812	940	13	3	19	5	17	17	17	51	\N	\N	51	12	00:01:38.595	12
22813	940	834	209	53	19	18	18	18	51	\N	\N	35	20	00:01:41.467	12
22814	940	829	209	28	18	19	19	19	50	\N	\N	44	19	00:01:41.452	13
22815	940	831	15	12	16	\N	R	20	49	\N	\N	39	17	00:01:40.088	31
22816	941	1	131	44	2	1	1	1	53	1:37:11.024	5831024	44	3	00:01:40.573	1
22817	941	20	6	5	4	2	2	2	53	+5.953	5836977	51	1	00:01:40.071	1
22818	941	815	10	11	7	3	3	3	53	+28.918	5859942	48	9	00:01:41.772	1
22819	941	13	3	19	15	4	4	4	53	+38.831	5869855	48	4	00:01:40.881	1
22820	941	8	6	7	5	8	8	8	53	+1:12.358	5903382	48	2	00:01:40.294	1
22821	941	831	15	12	12	6	6	6	53	+56.508	5887532	52	6	00:01:41.372	1
22822	941	813	208	13	14	7	7	7	53	+1:01.088	5892112	52	7	00:01:41.507	1
22824	941	18	1	22	13	9	9	9	53	+1:19.467	5910491	53	13	00:01:43.068	1
22825	941	830	5	33	9	10	10	10	53	+1:28.424	5919448	45	15	00:01:43.265	1
22826	941	4	1	14	19	11	11	11	53	+1:31.210	5922234	29	12	00:01:42.639	1
22827	941	822	3	77	3	12	12	12	52	\N	\N	45	5	00:01:41.134	4
22828	941	833	209	98	18	13	13	13	52	\N	\N	50	17	00:01:45.049	11
22829	941	829	209	28	17	14	14	14	51	\N	\N	50	16	00:01:44.926	12
22830	941	817	9	3	10	15	15	15	47	\N	\N	43	10	00:01:41.888	22
22831	941	832	5	55	20	\N	R	16	45	\N	\N	44	11	00:01:42.258	23
22832	941	154	208	8	8	\N	R	17	11	\N	\N	7	18	00:01:45.266	3
22833	941	3	131	6	1	\N	R	18	7	\N	\N	6	14	00:01:43.133	37
22834	941	807	10	27	6	\N	R	19	0	\N	\N	\N	0	\N	4
22835	941	828	15	9	17	\N	R	20	0	\N	\N	\N	0	\N	4
22837	942	1	131	44	2	1	1	1	56	1:50:52.703	6652703	48	2	00:01:40.738	1
22836	941	826	9	26	11	5	5	5	53	+47.566	5878590	\N	0	\N	1
22838	942	3	131	6	1	2	2	2	56	+2.850	6655553	49	1	00:01:40.666	1
22839	942	20	6	5	13	3	3	3	56	+3.381	6656084	52	3	00:01:41.33	1
22840	942	830	5	33	8	4	4	4	56	+22.359	6675062	51	9	00:01:43.172	1
22841	942	815	10	11	5	5	5	5	56	+24.413	6677116	54	7	00:01:43.01	1
22842	942	18	1	22	11	6	6	6	56	+28.058	6680761	50	8	00:01:43.026	1
22843	942	832	5	55	20	7	7	7	56	+30.619	6683322	51	5	00:01:42.66	1
22844	942	813	208	13	12	8	8	8	56	+32.273	6684976	51	6	00:01:42.849	1
22845	942	831	15	12	15	9	9	9	56	+40.257	6692960	54	12	00:01:44.407	1
22846	942	817	9	3	3	10	10	10	56	+53.371	6706074	53	4	00:01:41.98	1
22847	942	4	1	14	9	11	11	11	56	+54.816	6707519	55	11	00:01:44.323	1
22848	942	834	209	53	17	12	12	12	56	+1:15.277	6727980	50	16	00:01:48.173	1
22849	942	826	9	26	4	\N	R	13	41	\N	\N	41	10	00:01:43.728	3
22850	942	807	10	27	6	\N	R	14	35	\N	\N	24	13	00:01:45.095	3
22851	942	828	15	9	14	\N	R	15	25	\N	\N	24	15	00:01:47.381	31
22852	942	8	6	7	18	\N	R	16	25	\N	\N	24	14	00:01:46.186	135
22853	942	13	3	19	7	\N	R	17	23	\N	\N	22	17	00:01:48.231	31
22854	942	154	208	8	10	\N	R	18	10	\N	\N	8	18	00:01:59.612	31
22855	942	822	3	77	16	\N	R	19	5	\N	\N	3	19	00:02:31.939	31
22856	942	829	209	28	19	\N	R	20	1	\N	\N	\N	0	\N	31
22857	943	3	131	6	1	1	1	1	71	1:42:35.038	6155038	67	1	00:01:20.521	1
22858	943	1	131	44	2	2	2	2	71	+1.954	6156992	67	2	00:01:20.723	1
22859	943	822	3	77	6	3	3	3	71	+14.592	6169630	68	4	00:01:21.585	1
22860	943	826	9	26	4	4	4	4	71	+16.572	6171610	69	3	00:01:21.549	1
22861	943	817	9	3	5	5	5	5	71	+19.682	6174720	70	5	00:01:21.625	1
22862	943	13	3	19	7	6	6	6	71	+21.493	6176531	71	7	00:01:22.009	1
22863	943	807	10	27	10	7	7	7	71	+25.860	6180898	69	9	00:01:22.391	1
22864	943	815	10	11	9	8	8	8	71	+34.343	6189381	51	12	00:01:22.757	1
22865	943	830	5	33	8	9	9	9	71	+35.229	6190267	70	10	00:01:22.603	1
22866	943	154	208	8	12	10	10	10	71	+37.934	6192972	69	13	00:01:22.893	1
22867	943	813	208	13	13	11	11	11	71	+38.538	6193576	70	14	00:01:22.963	1
22868	943	828	15	9	14	12	12	12	71	+40.180	6195218	62	11	00:01:22.716	1
22869	943	832	5	55	11	13	13	13	71	+48.772	6203810	46	8	00:01:22.172	1
22870	943	18	1	22	20	14	14	14	71	+49.214	6204252	49	15	00:01:23.006	1
22871	943	834	209	53	16	15	15	15	69	\N	\N	69	18	00:01:25.005	12
22872	943	829	209	28	17	16	16	16	69	\N	\N	67	19	00:01:25.54	12
22873	943	831	15	12	15	\N	R	17	57	\N	\N	48	16	00:01:23.35	23
22874	943	20	6	5	3	\N	R	18	50	\N	\N	48	6	00:01:21.847	3
22875	943	8	6	7	19	\N	R	19	21	\N	\N	20	17	00:01:24.054	4
22876	943	4	1	14	18	\N	R	20	1	\N	\N	\N	0	\N	31
22877	944	3	131	6	1	1	1	1	71	1:31:09.090	5469090	57	2	00:01:14.957	1
22878	944	1	131	44	2	2	2	2	71	+7.756	5476846	51	1	00:01:14.832	1
22879	944	20	6	5	3	3	3	3	71	+14.244	5483334	57	3	00:01:15.046	1
22880	944	8	6	7	4	4	4	4	71	+47.543	5516633	48	4	00:01:15.416	1
22881	944	822	3	77	7	5	5	5	70	\N	\N	61	10	00:01:16.039	11
22882	944	807	10	27	5	6	6	6	70	\N	\N	66	16	00:01:16.774	11
22883	944	826	9	26	6	7	7	7	70	\N	\N	41	14	00:01:16.5	11
22884	944	154	208	8	14	8	8	8	70	\N	\N	57	5	00:01:15.739	11
22885	944	830	5	33	9	9	9	9	70	\N	\N	56	9	00:01:15.972	11
22886	944	813	208	13	15	10	10	10	70	\N	\N	63	13	00:01:16.354	11
22887	944	817	9	3	19	11	11	11	70	\N	\N	56	11	00:01:16.313	11
22888	944	815	10	11	11	12	12	12	70	\N	\N	53	8	00:01:15.97	11
22889	944	831	15	12	13	13	13	13	70	\N	\N	41	17	00:01:16.794	11
22890	944	18	1	22	16	14	14	14	70	\N	\N	53	12	00:01:16.321	11
22891	944	4	1	14	20	15	15	15	70	\N	\N	54	15	00:01:16.519	11
22892	944	828	15	9	12	16	16	16	69	\N	\N	57	7	00:01:15.789	12
22893	944	829	209	28	18	17	17	17	67	\N	\N	42	19	00:01:19.098	14
22894	944	834	209	53	17	18	18	18	67	\N	\N	43	18	00:01:18.617	14
22895	944	832	5	55	10	\N	R	19	0	\N	\N	\N	0	\N	31
22896	944	13	3	19	8	\N	E	20	70	\N	\N	57	6	00:01:15.743	96
22897	945	3	131	6	1	1	1	1	55	1:38:30.175	5910175	37	5	00:01:45.356	1
22898	945	1	131	44	2	2	2	2	55	+8.271	5918446	44	1	00:01:44.517	1
22899	945	8	6	7	3	3	3	3	55	+19.430	5929605	47	4	00:01:44.942	1
22900	945	20	6	5	15	4	4	4	55	+43.735	5953910	48	2	00:01:44.55	1
22901	945	815	10	11	4	5	5	5	55	+1:03.952	5974127	30	8	00:01:45.892	1
22902	945	817	9	3	5	6	6	6	55	+1:05.010	5975185	46	9	00:01:46.305	1
22903	945	807	10	27	7	7	7	7	55	+1:33.618	6003793	29	16	00:01:47.064	1
22904	945	13	3	19	8	8	8	8	55	+1:37.751	6007926	33	14	00:01:46.984	1
22905	945	154	208	8	18	9	9	9	55	+1:38.201	6008376	47	7	00:01:45.859	1
22906	945	826	9	26	9	10	10	10	55	+1:42.371	6012546	27	13	00:01:46.882	1
22907	945	832	5	55	10	11	11	11	55	+1:43.525	6013700	38	15	00:01:46.998	1
22908	945	18	1	22	12	12	12	12	54	\N	\N	29	17	00:01:47.509	11
22909	945	822	3	77	6	13	13	13	54	\N	\N	45	11	00:01:46.464	11
22910	945	828	15	9	17	14	14	14	54	\N	\N	48	12	00:01:46.517	11
22911	945	831	15	12	14	15	15	15	54	\N	\N	46	10	00:01:46.424	11
22912	945	830	5	33	11	16	16	16	54	\N	\N	40	6	00:01:45.746	11
22913	945	4	1	14	16	17	17	17	53	\N	\N	52	3	00:01:44.796	12
22914	945	829	209	28	19	18	18	18	53	\N	\N	53	18	00:01:49.61	12
22915	945	833	209	98	20	19	19	19	52	\N	\N	26	19	00:01:51.213	13
22916	945	813	208	13	13	\N	R	20	0	\N	\N	\N	0	\N	4
22917	948	3	131	6	2	1	1	1	57	1:48:15.565	6495565	21	3	00:01:30.557	1
22918	948	1	131	44	1	2	2	2	57	+8.060	6503625	48	4	00:01:30.646	1
22919	948	20	6	5	3	3	3	3	57	+9.643	6505208	23	2	00:01:29.951	1
22920	948	817	9	3	8	4	4	4	57	+24.330	6519895	49	1	00:01:28.997	1
22921	948	13	3	19	6	5	5	5	57	+58.979	6554544	39	9	00:01:32.288	1
22922	948	154	210	8	19	6	6	6	57	+1:12.081	6567646	48	17	00:01:32.862	1
22923	948	807	10	27	10	7	7	7	57	+1:14.199	6569764	49	16	00:01:32.833	1
22924	948	822	3	77	16	8	8	8	57	+1:15.153	6570718	51	14	00:01:32.725	1
22925	948	832	5	55	7	9	9	9	57	+1:15.680	6571245	23	7	00:01:31.671	1
22926	948	830	5	33	5	10	10	10	57	+1:16.833	6572398	44	6	00:01:31.516	1
22927	948	835	4	30	13	11	11	11	57	+1:23.399	6578964	14	18	00:01:32.955	1
22928	948	825	4	20	14	12	12	12	57	+1:25.606	6581171	45	10	00:01:32.452	1
22929	948	815	10	11	9	13	13	13	57	+1:31.699	6587264	39	15	00:01:32.78	1
22930	948	18	1	22	12	14	14	14	56	\N	\N	33	8	00:01:31.684	11
22931	948	831	15	12	17	15	15	15	56	\N	\N	48	13	00:01:32.711	11
22932	948	836	209	94	21	16	16	16	56	\N	\N	34	12	00:01:32.673	11
22933	948	828	15	9	15	\N	R	17	38	\N	\N	15	21	00:01:33.892	5
22934	948	8	6	7	4	\N	R	18	21	\N	\N	21	5	00:01:30.701	5
22935	948	837	209	88	22	\N	R	19	17	\N	\N	15	20	00:01:33.847	26
22936	948	821	210	21	20	\N	R	20	16	\N	\N	4	19	00:01:32.998	4
22937	948	4	1	14	11	\N	R	21	16	\N	\N	14	11	00:01:32.553	4
22938	948	826	9	26	18	\N	W	22	0	\N	\N	\N	0	\N	31
22939	949	3	131	6	2	1	1	1	57	1:33:34.696	5614696	41	1	00:01:34.482	1
22940	949	8	6	7	4	2	2	2	57	+10.282	5624978	39	3	00:01:35.158	1
22941	949	1	131	44	1	3	3	3	57	+30.148	5644844	43	2	00:01:34.677	1
22942	949	817	9	3	5	4	4	4	57	+1:02.494	5677190	44	9	00:01:36.064	1
22943	949	154	210	8	9	5	5	5	57	+1:18.299	5692995	42	11	00:01:36.095	1
22944	949	830	5	33	10	6	6	6	57	+1:20.929	5695625	49	7	00:01:35.504	1
22945	949	826	9	26	15	7	7	7	56	\N	\N	36	8	00:01:35.678	11
22946	949	13	3	19	7	8	8	8	56	\N	\N	31	16	00:01:37.56	11
22947	949	822	3	77	6	9	9	9	56	\N	\N	37	15	00:01:37.077	11
22948	949	838	1	47	12	10	10	10	56	\N	\N	44	12	00:01:36.121	11
22949	949	825	4	20	22	11	11	11	56	\N	\N	40	14	00:01:36.73	11
22950	949	828	15	9	17	12	12	12	56	\N	\N	32	17	00:01:38.003	11
22951	949	836	209	94	16	13	13	13	56	\N	\N	43	6	00:01:35.448	11
22952	949	831	15	12	21	14	14	14	56	\N	\N	49	5	00:01:35.36	11
22953	949	807	10	27	8	15	15	15	56	\N	\N	53	4	00:01:35.188	11
22954	949	815	10	11	18	16	16	16	56	\N	\N	39	10	00:01:36.067	11
22955	949	837	209	88	20	17	17	17	56	\N	\N	47	13	00:01:36.685	11
22956	949	832	5	55	11	\N	R	18	29	\N	\N	22	18	00:01:38.408	31
22957	949	821	210	21	13	\N	R	19	9	\N	\N	2	19	00:01:39.341	31
22958	949	18	1	22	14	\N	R	20	6	\N	\N	3	20	00:01:39.427	131
22959	949	20	6	5	3	\N	W	21	0	\N	\N	\N	0	\N	5
22960	949	835	4	30	19	\N	W	22	0	\N	\N	\N	0	\N	9
22961	950	3	131	6	1	1	1	1	56	1:38:53.891	5933891	38	6	00:01:40.418	1
22962	950	20	6	5	4	2	2	2	56	+37.776	5971667	37	9	00:01:40.61	1
22963	950	826	9	26	6	3	3	3	56	+45.936	5979827	38	14	00:01:41.546	1
22964	950	817	9	3	2	4	4	4	56	+52.688	5986579	55	11	00:01:41.015	1
22965	950	8	6	7	3	5	5	5	56	+1:05.872	5999763	40	8	00:01:40.593	1
22966	950	13	3	19	10	6	6	6	56	+1:15.511	6009402	34	16	00:01:41.815	1
22967	950	1	131	44	22	7	7	7	56	+1:18.230	6012121	32	10	00:01:40.662	1
22968	950	830	5	33	9	8	8	8	56	+1:19.268	6013159	41	5	00:01:40.399	1
22969	950	832	5	55	8	9	9	9	56	+1:24.127	6018018	35	12	00:01:41.485	1
22970	950	822	3	77	5	10	10	10	56	+1:26.192	6020083	23	15	00:01:41.558	1
22971	950	815	10	11	7	11	11	11	56	+1:34.283	6028174	30	17	00:01:41.846	1
22972	950	4	1	14	11	12	12	12	56	+1:37.253	6031144	36	19	00:01:42.226	1
22973	950	18	1	22	12	13	13	13	56	+1:41.990	6035881	46	3	00:01:40.298	1
22974	950	821	210	21	18	14	14	14	55	\N	\N	45	4	00:01:40.368	11
22975	950	807	10	27	13	15	15	15	55	\N	\N	48	1	00:01:39.824	11
22976	950	828	15	9	15	16	16	16	55	\N	\N	41	22	00:01:43.269	11
22977	950	825	4	20	17	17	17	17	55	\N	\N	22	21	00:01:42.311	11
22978	950	836	209	94	21	18	18	18	55	\N	\N	48	13	00:01:41.489	11
22979	950	154	210	8	14	19	19	19	55	\N	\N	47	2	00:01:39.923	11
22980	950	831	15	12	16	20	20	20	55	\N	\N	42	7	00:01:40.582	11
22981	950	837	209	88	20	21	21	21	55	\N	\N	42	18	00:01:42.009	11
22982	950	835	4	30	19	22	22	22	55	\N	\N	26	20	00:01:42.232	11
22983	951	3	131	6	1	1	1	1	53	1:32:41.997	5561997	52	1	00:01:39.094	1
22984	951	1	131	44	10	2	2	2	53	+25.022	5587019	36	4	00:01:40.266	1
22985	951	8	6	7	3	3	3	3	53	+31.998	5593995	47	3	00:01:40.101	1
22986	951	822	3	77	2	4	4	4	53	+50.217	5612214	37	6	00:01:41.159	1
22987	951	13	3	19	4	5	5	5	53	+1:14.427	5636424	52	2	00:01:39.743	1
22988	951	4	1	14	14	6	6	6	52	\N	\N	52	5	00:01:40.347	11
22989	951	825	4	20	17	7	7	7	52	\N	\N	50	9	00:01:41.832	11
22990	951	154	210	8	15	8	8	8	52	\N	\N	51	12	00:01:42.026	11
22991	951	815	10	11	6	9	9	9	52	\N	\N	47	10	00:01:41.897	11
22992	951	18	1	22	12	10	10	10	52	\N	\N	50	8	00:01:41.72	11
22993	951	817	9	3	5	11	11	11	52	\N	\N	46	7	00:01:41.179	11
22994	951	832	5	55	11	12	12	12	52	\N	\N	41	15	00:01:42.205	11
22995	951	835	4	30	18	13	13	13	52	\N	\N	37	19	00:01:42.66	11
22996	951	828	15	9	22	14	14	14	52	\N	\N	45	14	00:01:42.05	11
22997	951	826	9	26	8	15	15	15	52	\N	\N	44	17	00:01:42.344	11
22998	951	831	15	12	19	16	16	16	52	\N	\N	50	16	00:01:42.253	11
22999	951	821	210	21	16	17	17	17	52	\N	\N	52	18	00:01:42.378	11
23000	951	836	209	94	20	18	18	18	51	\N	\N	43	11	00:01:41.907	12
23001	951	830	5	33	9	\N	R	19	33	\N	\N	32	13	00:01:42.029	131
23002	951	20	6	5	7	\N	R	20	0	\N	\N	\N	0	\N	4
23003	951	807	10	27	13	\N	R	21	0	\N	\N	\N	0	\N	4
23004	951	837	209	88	21	\N	R	22	0	\N	\N	\N	0	\N	4
23005	952	830	9	33	4	1	1	1	66	1:41:40.017	6100017	36	6	00:01:28.816	1
23006	952	8	6	7	5	2	2	2	66	+0.616	6100633	38	4	00:01:28.538	1
23007	952	20	6	5	6	3	3	3	66	+5.581	6105598	39	2	00:01:27.974	1
23008	952	817	9	3	3	4	4	4	66	+43.950	6143967	46	3	00:01:28.209	1
23009	952	822	3	77	7	5	5	5	66	+45.271	6145288	60	8	00:01:29.081	1
23010	952	832	5	55	8	6	6	6	66	+1:01.395	6161412	42	11	00:01:29.663	1
23011	952	815	10	11	9	7	7	7	66	+1:19.538	6179555	37	15	00:01:29.801	1
23012	952	13	3	19	18	8	8	8	66	+1:20.707	6180724	43	9	00:01:29.238	1
23013	952	18	1	22	12	9	9	9	65	\N	\N	39	18	00:01:30.26	11
23014	952	826	5	26	13	10	10	10	65	\N	\N	53	1	00:01:26.948	11
23015	952	821	210	21	16	11	11	11	65	\N	\N	34	17	00:01:30.139	11
23016	952	828	15	9	19	12	12	12	65	\N	\N	42	12	00:01:29.715	11
23017	952	835	4	30	17	13	13	13	65	\N	\N	35	14	00:01:29.779	11
23018	952	825	4	20	15	14	14	14	65	\N	\N	57	5	00:01:28.716	11
23019	952	831	15	12	20	15	15	15	65	\N	\N	38	16	00:01:29.905	11
23020	952	836	209	94	21	16	16	16	65	\N	\N	37	19	00:01:31.182	11
23021	952	837	209	88	22	17	17	17	65	\N	\N	52	10	00:01:29.402	11
23022	952	154	210	8	14	\N	R	18	56	\N	\N	41	7	00:01:28.974	5
23023	952	4	1	14	10	\N	R	19	45	\N	\N	41	13	00:01:29.75	5
23024	952	807	10	27	11	\N	R	20	20	\N	\N	8	20	00:01:31.81	5
23025	952	1	131	44	1	\N	R	21	0	\N	\N	\N	0	\N	4
23026	952	3	131	6	2	\N	R	22	0	\N	\N	\N	0	\N	4
23027	953	1	131	44	3	1	1	1	78	1:59:29.133	7169133	71	1	00:01:17.939	1
23028	953	817	9	3	1	2	2	2	78	+7.252	7176385	67	3	00:01:18.294	1
23029	953	815	10	11	7	3	3	3	78	+13.825	7182958	64	4	00:01:18.446	1
23030	953	20	6	5	4	4	4	4	78	+15.846	7184979	62	2	00:01:18.005	1
23031	953	4	1	14	9	5	5	5	78	+1:25.076	7254209	72	8	00:01:19.17	1
23032	953	807	10	27	5	6	6	6	78	+1:32.999	7262132	74	11	00:01:19.232	1
23033	953	3	131	6	2	7	7	7	78	+1:33.290	7262423	74	6	00:01:18.763	1
23034	953	832	5	55	6	8	8	8	77	\N	\N	70	5	00:01:18.519	11
23035	953	18	1	22	13	9	9	9	77	\N	\N	66	12	00:01:19.67	11
23036	953	13	3	19	14	10	10	10	77	\N	\N	69	9	00:01:19.213	11
23037	953	821	210	21	12	11	11	11	77	\N	\N	69	7	00:01:19.131	11
23038	953	822	3	77	10	12	12	12	77	\N	\N	66	10	00:01:19.223	11
23039	953	154	210	8	15	13	13	13	76	\N	\N	65	14	00:01:20.219	12
23040	953	836	209	94	20	14	14	14	76	\N	\N	60	15	00:01:20.372	12
23041	953	837	209	88	19	15	15	15	74	\N	\N	70	13	00:01:19.868	14
23042	953	828	15	9	17	\N	R	16	51	\N	\N	51	16	00:01:21.342	4
23043	953	831	15	12	0	\N	R	17	48	\N	\N	46	17	00:01:21.889	31
23044	953	830	9	33	0	\N	R	18	34	\N	\N	34	18	00:01:26.563	3
23045	953	825	4	20	16	\N	R	19	32	\N	\N	27	19	00:01:29.802	31
23046	953	826	5	26	8	\N	R	20	18	\N	\N	14	20	00:01:37.895	3
23047	953	8	6	7	11	\N	R	21	10	\N	\N	10	21	00:01:47.149	3
23048	953	835	4	30	18	\N	R	22	7	\N	\N	2	22	00:01:58.474	3
23049	954	1	131	44	1	1	1	1	70	1:31:05.296	5465296	68	2	00:01:15.981	1
23050	954	20	6	5	3	2	2	2	70	+5.011	5470307	70	3	00:01:16.297	1
23051	954	822	3	77	7	3	3	3	70	+46.422	5511718	68	10	00:01:16.938	1
23052	954	830	9	33	5	4	4	4	70	+53.020	5518316	49	4	00:01:16.319	1
23053	954	3	131	6	2	5	5	5	70	+1:02.093	5527389	60	1	00:01:15.599	1
23054	954	8	6	7	6	6	6	6	70	+1:03.017	5528313	44	9	00:01:16.919	1
23055	954	817	9	3	4	7	7	7	70	+1:03.634	5528930	51	5	00:01:16.506	1
23056	954	807	10	27	9	8	8	8	69	\N	\N	68	8	00:01:16.604	11
23057	954	832	5	55	20	9	9	9	69	\N	\N	54	7	00:01:16.578	11
23058	954	815	10	11	11	10	10	10	69	\N	\N	54	6	00:01:16.559	11
23059	954	4	1	14	10	11	11	11	69	\N	\N	67	13	00:01:17.307	11
23060	954	826	5	26	15	12	12	12	69	\N	\N	50	11	00:01:16.942	11
23061	954	821	210	21	13	13	13	13	68	\N	\N	48	15	00:01:17.728	12
23062	954	154	210	8	14	14	14	14	68	\N	\N	50	12	00:01:17.281	12
23063	954	828	15	9	21	15	15	15	68	\N	\N	63	17	00:01:18.1	12
23064	954	825	4	20	22	16	16	16	68	\N	\N	42	18	00:01:18.224	12
23065	954	836	209	94	17	17	17	17	68	\N	\N	48	19	00:01:18.282	12
23066	954	831	15	12	18	18	18	18	68	\N	\N	66	16	00:01:17.883	12
23067	954	837	209	88	19	19	19	19	68	\N	\N	57	20	00:01:18.658	12
23068	954	13	3	19	8	\N	R	20	35	\N	\N	32	14	00:01:17.424	31
23069	954	835	4	30	16	\N	R	21	16	\N	\N	6	22	00:01:19.879	31
23070	954	18	1	22	12	\N	R	22	9	\N	\N	5	21	00:01:19.456	131
23071	955	3	131	6	1	1	1	1	51	1:32:52.366	5572366	48	1	00:01:46.485	1
23072	955	20	6	5	3	2	2	2	51	+16.696	5589062	49	5	00:01:47.028	1
23073	955	815	10	11	7	3	3	3	51	+25.241	5597607	45	4	00:01:46.99	1
23074	955	8	6	7	4	4	4	4	51	+33.102	5605468	41	6	00:01:47.181	1
23075	955	1	131	44	10	5	5	5	51	+56.335	5628701	42	2	00:01:46.822	1
23076	955	822	3	77	8	6	6	6	51	+1:00.886	5633252	50	9	00:01:47.604	1
23077	955	817	9	3	2	7	7	7	51	+1:09.229	5641595	51	12	00:01:47.736	1
23078	955	830	9	33	9	8	8	8	51	+1:10.696	5643062	50	3	00:01:46.973	1
23079	955	807	10	27	12	9	9	9	51	+1:17.708	5650074	37	15	00:01:48.012	1
23080	955	13	3	19	5	10	10	10	51	+1:25.375	5657741	35	13	00:01:47.761	1
23081	955	18	1	22	19	11	11	11	51	+1:44.817	5677183	50	10	00:01:47.622	1
23082	955	831	15	12	15	12	12	12	50	\N	\N	48	11	00:01:47.708	11
23083	955	154	210	8	11	13	13	13	50	\N	\N	48	14	00:01:47.943	11
23084	955	825	4	20	22	14	14	14	50	\N	\N	41	19	00:01:49.282	11
23085	955	835	4	30	21	15	15	15	50	\N	\N	48	8	00:01:47.583	11
23086	955	821	210	21	14	16	16	16	50	\N	\N	50	7	00:01:47.563	11
23087	955	828	15	9	20	17	17	17	50	\N	\N	48	17	00:01:48.898	11
23088	955	837	209	88	16	18	18	18	49	\N	\N	27	21	00:01:51.365	12
23089	955	4	1	14	13	\N	R	19	42	\N	\N	27	18	00:01:49.101	6
23090	955	836	209	94	17	\N	R	20	39	\N	\N	33	20	00:01:50.571	23
23091	955	832	5	55	18	\N	R	21	31	\N	\N	31	16	00:01:48.804	22
23092	955	826	5	26	6	\N	R	22	6	\N	\N	2	22	00:01:53.167	22
23093	956	1	131	44	1	1	1	1	71	1:27:38.107	5258107	67	1	00:01:08.411	1
23094	956	830	9	33	8	2	2	2	71	+5.719	5263826	69	5	00:01:09.618	1
23095	956	8	6	7	4	3	3	3	71	+6.024	5264131	66	4	00:01:08.876	1
23096	956	3	131	6	6	4	4	4	71	+16.710	5274817	66	2	00:01:08.491	1
23097	956	817	9	3	5	5	5	5	71	+30.981	5289088	66	3	00:01:08.77	1
23098	956	18	1	22	3	6	6	6	71	+37.706	5295813	70	9	00:01:10.001	1
23099	956	154	210	8	13	7	7	7	71	+44.668	5302775	67	8	00:01:09.925	1
23100	956	832	5	55	15	8	8	8	71	+47.400	5305507	68	11	00:01:10.138	1
23101	956	822	3	77	7	9	9	9	70	\N	\N	55	12	00:01:10.21	11
23102	956	836	209	94	12	10	10	10	70	\N	\N	67	19	00:01:10.859	11
23103	956	821	210	21	11	11	11	11	70	\N	\N	55	6	00:01:09.694	11
23104	956	835	4	30	19	12	12	12	70	\N	\N	53	13	00:01:10.228	11
23105	956	831	15	12	21	13	13	13	70	\N	\N	46	16	00:01:10.415	11
23106	956	825	4	20	17	14	14	14	70	\N	\N	56	17	00:01:10.45	11
23107	956	828	15	9	18	15	15	15	70	\N	\N	58	18	00:01:10.704	11
23108	956	837	209	88	20	16	16	16	70	\N	\N	66	15	00:01:10.342	11
23109	956	815	10	11	16	17	17	17	69	\N	\N	66	10	00:01:10.12	23
23110	956	4	1	14	14	18	18	18	64	\N	\N	44	20	00:01:11.02	84
23111	956	807	10	27	2	19	19	19	64	\N	\N	53	14	00:01:10.309	23
23112	956	13	3	19	10	20	20	20	63	\N	\N	59	7	00:01:09.899	23
23113	956	20	6	5	9	\N	R	21	26	\N	\N	10	21	00:01:11.441	27
23114	956	826	5	26	22	\N	R	22	2	\N	\N	2	22	00:01:18.302	31
23115	957	1	131	44	1	1	1	1	52	1:34:55.831	5695831	45	3	00:01:35.771	1
23116	957	830	9	33	3	2	2	2	52	+8.250	5704081	41	6	00:01:36.407	1
23117	957	3	131	6	2	3	3	3	52	+16.911	5712742	44	1	00:01:35.548	1
23118	957	817	9	3	4	4	4	4	52	+26.211	5722042	52	4	00:01:36.013	1
23119	957	8	6	7	5	5	5	5	52	+1:09.743	5765574	39	8	00:01:36.994	1
23120	957	815	10	11	10	6	6	6	52	+1:16.941	5772772	35	15	00:01:37.9	1
23121	957	807	10	27	8	7	7	7	52	+1:17.712	5773543	51	11	00:01:37.618	1
23122	957	832	5	55	7	8	8	8	52	+1:25.858	5781689	43	10	00:01:37.401	1
23123	957	20	6	5	11	9	9	9	52	+1:31.654	5787485	44	7	00:01:36.933	1
23124	957	826	5	26	15	10	10	10	52	+1:32.600	5788431	35	13	00:01:37.667	1
23125	957	13	3	19	12	11	11	11	51	\N	\N	40	5	00:01:36.141	11
23126	957	18	1	22	17	12	12	12	51	\N	\N	36	16	00:01:37.907	11
23127	957	4	1	14	9	13	13	13	51	\N	\N	43	2	00:01:35.669	11
23128	957	822	3	77	6	14	14	14	51	\N	\N	45	9	00:01:37.383	11
23129	957	831	15	12	21	15	15	15	51	\N	\N	43	17	00:01:38.71	11
23130	957	821	210	21	14	16	16	16	51	\N	\N	44	14	00:01:37.713	11
23131	957	825	4	20	16	17	17	17	49	\N	\N	43	12	00:01:37.619	6
23132	957	835	4	30	18	\N	R	18	37	\N	\N	36	18	00:01:39.755	6
23133	957	837	209	88	19	\N	R	19	24	\N	\N	23	19	00:01:41.38	20
23134	957	154	210	8	13	\N	R	20	17	\N	\N	14	20	00:01:55.507	31
23135	957	828	15	9	22	\N	R	21	11	\N	\N	9	21	00:02:00.286	131
23136	957	836	209	94	20	\N	R	22	6	\N	\N	4	22	00:02:48.804	20
23137	958	1	131	44	2	1	1	1	70	1:40:30.115	6030115	69	3	00:01:23.849	1
23138	958	3	131	6	1	2	2	2	70	+1.977	6032092	60	2	00:01:23.67	1
23139	958	817	9	3	3	3	3	3	70	+27.539	6057654	60	5	00:01:24.608	1
23140	958	20	6	5	5	4	4	4	70	+28.213	6058328	59	4	00:01:24.383	1
23141	958	830	9	33	4	5	5	5	70	+48.659	6078774	40	7	00:01:24.687	1
23142	958	8	6	7	14	6	6	6	70	+49.044	6079159	52	1	00:01:23.086	1
23143	958	4	1	14	7	7	7	7	69	\N	\N	62	8	00:01:24.958	11
23144	958	832	5	55	6	8	8	8	69	\N	\N	67	10	00:01:25.103	11
23145	958	822	3	77	10	9	9	9	69	\N	\N	59	11	00:01:25.273	11
23146	958	807	10	27	9	10	10	10	69	\N	\N	69	13	00:01:25.392	11
23147	958	815	10	11	13	11	11	11	69	\N	\N	65	9	00:01:25.021	11
23148	958	835	4	30	17	12	12	12	69	\N	\N	41	16	00:01:25.743	11
23149	958	821	210	21	15	13	13	13	69	\N	\N	39	17	00:01:25.955	11
23150	958	154	210	8	11	14	14	14	69	\N	\N	56	18	00:01:25.958	11
23151	958	825	4	20	19	15	15	15	69	\N	\N	39	19	00:01:26.23	11
23152	958	826	5	26	12	16	16	16	69	\N	\N	48	6	00:01:24.669	11
23153	958	831	15	12	16	17	17	17	69	\N	\N	66	15	00:01:25.676	11
23154	958	13	3	19	18	18	18	18	68	\N	\N	68	12	00:01:25.296	12
23155	958	836	209	94	20	19	19	19	68	\N	\N	47	20	00:01:26.524	12
23156	958	828	15	9	22	20	20	20	68	\N	\N	47	14	00:01:25.475	12
23157	958	837	209	88	21	21	21	21	68	\N	\N	64	22	00:01:27.791	12
23158	958	18	1	22	8	\N	R	22	60	\N	\N	9	21	00:01:26.744	44
23159	959	1	131	44	2	1	1	1	67	1:30:44.200	5444200	52	3	00:01:18.746	1
23160	959	817	9	3	3	2	2	2	67	+6.996	5451196	48	1	00:01:18.442	1
23161	959	830	9	33	4	3	3	3	67	+13.413	5457613	47	4	00:01:18.91	1
23162	959	3	131	6	1	4	4	4	67	+15.845	5460045	51	5	00:01:19.122	1
23163	959	20	6	5	6	5	5	5	67	+32.570	5476770	48	2	00:01:18.71	1
23164	959	8	6	7	5	6	6	6	67	+37.023	5481223	36	6	00:01:19.572	1
23165	959	807	10	27	8	7	7	7	67	+1:10.049	5514249	46	12	00:01:20.056	1
23166	959	18	1	22	12	8	8	8	66	\N	\N	48	9	00:01:19.781	11
23167	959	822	3	77	7	9	9	9	66	\N	\N	36	15	00:01:20.442	11
23168	959	815	10	11	9	10	10	10	66	\N	\N	46	8	00:01:19.606	11
23169	959	821	210	21	11	11	11	11	66	\N	\N	56	10	00:01:19.883	11
23170	959	4	1	14	13	12	12	12	66	\N	\N	50	13	00:01:20.132	11
23171	959	154	210	8	20	13	13	13	66	\N	\N	58	14	00:01:20.25	11
23172	959	832	5	55	15	14	14	14	66	\N	\N	54	11	00:01:19.957	11
23173	959	826	5	26	18	15	15	15	66	\N	\N	51	7	00:01:19.585	11
23174	959	825	4	20	16	16	16	16	66	\N	\N	42	21	00:01:21.649	11
23175	959	836	209	94	17	17	17	17	65	\N	\N	49	16	00:01:20.71	12
23176	959	828	15	9	22	18	18	18	65	\N	\N	35	18	00:01:21.212	12
23177	959	835	4	30	14	19	19	19	65	\N	\N	55	17	00:01:21.127	12
23178	959	837	209	88	19	20	20	20	65	\N	\N	56	22	00:01:21.845	12
23179	959	831	15	12	21	\N	R	21	57	\N	\N	45	19	00:01:21.42	131
23180	959	13	3	19	10	\N	R	22	36	\N	\N	31	20	00:01:21.476	22
23181	960	3	131	6	1	1	1	1	44	1:44:51.058	6291058	11	2	00:01:51.746	1
23182	960	817	9	3	5	2	2	2	44	+14.113	6305171	11	4	00:01:52.461	1
23183	960	1	131	44	21	3	3	3	44	+27.634	6318692	40	1	00:01:51.583	1
23184	960	807	10	27	7	4	4	4	44	+35.907	6326965	41	10	00:01:53.53	1
23185	960	815	10	11	6	5	5	5	44	+40.660	6331718	34	8	00:01:53.414	1
23186	960	20	6	5	4	6	6	6	44	+45.394	6336452	35	5	00:01:52.728	1
23187	960	4	1	14	22	7	7	7	44	+59.445	6350503	43	15	00:01:54.484	1
23188	960	822	3	77	8	8	8	8	44	+1:00.151	6351209	31	12	00:01:54.12	1
23189	960	8	6	7	3	9	9	9	44	+1:01.109	6352167	27	9	00:01:53.498	1
23190	960	13	3	19	10	10	10	10	44	+1:05.873	6356931	25	14	00:01:54.342	1
23191	960	830	9	33	2	11	11	11	44	+1:11.138	6362196	32	7	00:01:53.281	1
23192	960	821	210	21	18	12	12	12	44	+1:13.877	6364935	26	13	00:01:54.335	1
23193	960	154	210	8	11	13	13	13	44	+1:16.474	6367532	25	11	00:01:53.803	1
23194	960	826	5	26	19	14	14	14	44	+1:27.097	6378155	37	3	00:01:52.081	1
23195	960	835	4	30	13	15	15	15	44	+1:33.165	6384223	41	6	00:01:53.251	1
23196	960	839	209	31	17	16	16	16	43	\N	\N	26	16	00:01:55.734	11
23197	960	831	15	12	16	17	17	17	43	\N	\N	31	17	00:01:56.152	11
23198	960	825	4	20	12	\N	R	18	5	\N	\N	4	18	00:01:56.588	3
23199	960	828	15	9	20	\N	R	19	3	\N	\N	2	19	00:02:15.255	6
23200	960	832	5	55	14	\N	R	20	1	\N	\N	\N	0	\N	29
23201	960	18	1	22	9	\N	R	21	1	\N	\N	\N	0	\N	130
23202	960	836	209	94	15	\N	R	22	0	\N	\N	\N	0	\N	130
23203	961	3	131	6	2	1	1	1	53	1:17:28.089	4648089	26	9	00:01:26.599	1
23204	961	1	131	44	1	2	2	2	53	+15.070	4663159	27	4	00:01:26.303	1
23205	961	20	6	5	3	3	3	3	53	+20.990	4669079	48	5	00:01:26.31	1
23206	961	8	6	7	4	4	4	4	53	+27.561	4675650	50	3	00:01:26.016	1
23207	961	817	9	3	6	5	5	5	53	+45.295	4693384	52	2	00:01:25.919	1
23208	961	822	3	77	5	6	6	6	53	+51.015	4699104	46	10	00:01:26.708	1
23209	961	830	9	33	7	7	7	7	53	+54.236	4702325	50	8	00:01:26.405	1
23210	961	815	10	11	8	8	8	8	53	+1:04.954	4713043	40	12	00:01:26.92	1
23211	961	13	3	19	11	9	9	9	53	+1:05.617	4713706	50	7	00:01:26.4	1
23212	961	807	10	27	9	10	10	10	53	+1:18.656	4726745	40	13	00:01:26.954	1
23213	961	154	210	8	17	11	11	11	52	\N	\N	50	15	00:01:27.227	11
23214	961	18	1	22	14	12	12	12	52	\N	\N	40	6	00:01:26.354	11
23215	961	821	210	21	10	13	13	13	52	\N	\N	42	14	00:01:27.106	11
23216	961	4	1	14	12	14	14	14	52	\N	\N	51	1	00:01:25.34	11
23217	961	832	5	55	15	15	15	15	52	\N	\N	41	11	00:01:26.751	11
23218	961	828	15	9	19	16	16	16	52	\N	\N	37	19	00:01:28.552	11
23219	961	825	4	20	21	17	17	17	52	\N	\N	52	16	00:01:27.618	11
23220	961	839	209	31	22	18	18	18	51	\N	\N	51	18	00:01:28.534	12
23221	961	826	5	26	16	\N	R	19	36	\N	\N	35	17	00:01:28.037	84
23222	961	836	209	94	13	\N	R	20	26	\N	\N	18	20	00:01:28.723	44
23223	961	835	4	30	20	\N	R	21	7	\N	\N	4	21	00:01:31.361	130
23224	961	831	15	12	18	\N	R	22	6	\N	\N	\N	0	\N	130
23225	962	3	131	6	1	1	1	1	61	1:55:48.950	6948950	38	6	00:01:50.296	1
23226	962	817	9	3	2	2	2	2	61	+0.488	6949438	49	1	00:01:47.187	1
23227	962	1	131	44	3	3	3	3	61	+8.038	6956988	52	3	00:01:47.752	1
23228	962	8	6	7	5	4	4	4	61	+10.219	6959169	51	4	00:01:48.204	1
23229	962	20	6	5	22	5	5	5	61	+27.694	6976644	45	2	00:01:47.345	1
23230	962	830	9	33	4	6	6	6	61	+1:11.197	7020147	46	5	00:01:49.05	1
23231	962	4	1	14	9	7	7	7	61	+1:29.198	7038148	49	12	00:01:51.249	1
23232	962	815	10	11	17	8	8	8	61	+1:51.062	7060012	34	15	00:01:51.517	1
23233	962	826	5	26	7	9	9	9	61	+1:51.557	7060507	39	9	00:01:50.944	1
23234	962	825	4	20	15	10	10	10	61	+1:59.952	7068902	44	8	00:01:50.858	1
23235	962	821	210	21	13	11	11	11	60	\N	\N	39	11	00:01:51.075	11
23236	962	13	3	19	11	12	12	12	60	\N	\N	53	14	00:01:51.455	11
23237	962	831	15	12	16	13	13	13	60	\N	\N	41	17	00:01:51.683	11
23238	962	832	5	55	6	14	14	14	60	\N	\N	56	7	00:01:50.532	11
23239	962	835	4	30	18	15	15	15	60	\N	\N	36	19	00:01:51.777	11
23240	962	836	209	94	19	16	16	16	60	\N	\N	40	20	00:01:52.021	11
23241	962	828	15	9	14	17	17	17	60	\N	\N	27	10	00:01:50.963	11
23242	962	839	209	31	21	18	18	18	59	\N	\N	47	18	00:01:51.748	12
23243	962	18	1	22	12	\N	R	19	43	\N	\N	18	16	00:01:51.631	23
23244	962	822	3	77	10	\N	R	20	35	\N	\N	17	13	00:01:51.368	25
23245	962	807	10	27	8	\N	R	21	0	\N	\N	\N	0	\N	4
23246	962	154	210	8	20	\N	W	22	0	\N	\N	\N	0	\N	54
23247	963	817	9	3	4	1	1	1	56	1:37:12.776	5832776	44	3	00:01:37.449	1
23248	963	830	9	33	3	2	2	2	56	+2.443	5835219	44	2	00:01:37.376	1
23249	963	3	131	6	2	3	3	3	56	+25.516	5858292	44	1	00:01:36.424	1
23250	963	8	6	7	6	4	4	4	56	+28.785	5861561	47	4	00:01:37.466	1
23251	963	822	3	77	11	5	5	5	56	+1:01.582	5894358	53	9	00:01:39.199	1
23252	963	815	10	11	7	6	6	6	56	+1:03.794	5896570	51	11	00:01:39.328	1
23253	963	4	1	14	22	7	7	7	56	+1:05.205	5897981	44	6	00:01:38.291	1
23254	963	807	10	27	8	8	8	8	56	+1:14.062	5906838	43	5	00:01:37.793	1
23255	963	18	1	22	9	9	9	9	56	+1:21.816	5914592	51	8	00:01:38.74	1
23256	963	835	4	30	19	10	10	10	56	+1:35.466	5928242	53	12	00:01:39.35	1
23257	963	832	5	55	16	11	11	11	56	+1:38.878	5931654	44	10	00:01:39.243	1
23258	963	828	15	9	17	12	12	12	55	\N	\N	55	14	00:01:39.781	11
23259	963	13	3	19	10	13	13	13	55	\N	\N	53	16	00:01:39.92	11
23260	963	826	5	26	15	14	14	14	55	\N	\N	43	15	00:01:39.798	11
23261	963	836	209	94	21	15	15	15	55	\N	\N	55	13	00:01:39.653	11
23262	963	839	209	31	20	16	16	16	55	\N	\N	45	18	00:01:41.467	11
23263	963	831	15	12	18	\N	R	17	46	\N	\N	43	17	00:01:40.49	23
23264	963	1	131	44	1	\N	R	18	40	\N	\N	31	7	00:01:38.595	5
23265	963	821	210	21	13	\N	R	19	39	\N	\N	37	19	00:01:41.775	61
23266	963	825	4	20	14	\N	R	20	17	\N	\N	3	21	00:01:43.379	75
23267	963	154	210	8	12	\N	R	21	7	\N	\N	7	20	00:01:42.142	23
23268	963	20	6	5	5	\N	R	22	0	\N	\N	\N	0	\N	4
23269	964	3	131	6	1	1	1	1	53	1:26:43.333	5203333	31	5	00:01:36.049	1
23270	964	830	9	33	3	2	2	2	53	+4.978	5208311	43	6	00:01:36.386	1
23271	964	1	131	44	2	3	3	3	53	+5.776	5209109	36	2	00:01:35.152	1
23272	964	20	6	5	6	4	4	4	53	+20.269	5223602	36	1	00:01:35.118	1
23273	964	8	6	7	8	5	5	5	53	+28.370	5231703	33	4	00:01:35.99	1
23274	964	817	9	3	4	6	6	6	53	+33.941	5237274	36	3	00:01:35.511	1
23275	964	815	10	11	5	7	7	7	53	+57.495	5260828	31	7	00:01:36.756	1
23276	964	807	10	27	9	8	8	8	53	+59.177	5262510	39	10	00:01:37.351	1
23277	964	13	3	19	12	9	9	9	53	+1:37.763	5301096	35	14	00:01:37.785	1
23278	964	822	3	77	11	10	10	10	53	+1:38.323	5301656	33	15	00:01:37.844	1
23279	964	154	210	8	7	11	11	11	53	+1:39.254	5302587	32	8	00:01:37.02	1
23280	964	835	4	30	16	12	12	12	52	\N	\N	43	16	00:01:37.978	11
23281	964	826	5	26	13	13	13	13	52	\N	\N	25	11	00:01:37.597	11
23282	964	825	4	20	17	14	14	14	52	\N	\N	27	18	00:01:38.036	11
23283	964	828	15	9	18	15	15	15	52	\N	\N	28	21	00:01:38.496	11
23284	964	4	1	14	15	16	16	16	52	\N	\N	29	19	00:01:38.208	11
23285	964	832	5	55	14	17	17	17	52	\N	\N	41	12	00:01:37.723	11
23286	964	18	1	22	22	18	18	18	52	\N	\N	39	9	00:01:37.177	11
23287	964	831	15	12	19	19	19	19	52	\N	\N	28	22	00:01:38.544	11
23288	964	821	210	21	10	20	20	20	52	\N	\N	30	13	00:01:37.775	11
23289	964	839	209	31	20	21	21	21	52	\N	\N	33	20	00:01:38.38	11
23290	964	836	209	94	21	22	22	22	52	\N	\N	39	17	00:01:38	11
23291	965	1	131	44	1	1	1	1	56	1:38:12.618	5892618	45	4	00:01:42.386	1
23292	965	3	131	6	2	2	2	2	56	+4.520	5897138	34	3	00:01:41.897	1
23293	965	817	9	3	3	3	3	3	56	+19.692	5912310	51	7	00:01:42.555	1
23294	965	20	6	5	6	4	4	4	56	+43.134	5935752	55	1	00:01:39.877	1
23295	965	4	1	14	12	5	5	5	56	+1:33.953	5986571	36	10	00:01:43.502	1
23296	965	832	5	55	10	6	6	6	56	+1:36.124	5988742	33	8	00:01:42.832	1
23297	965	13	3	19	9	7	7	7	55	\N	\N	33	9	00:01:43.414	11
23298	965	815	10	11	11	8	8	8	55	\N	\N	33	12	00:01:43.925	11
23299	965	18	1	22	19	9	9	9	55	\N	\N	37	15	00:01:44.468	11
23300	965	154	210	8	17	10	10	10	55	\N	\N	35	14	00:01:44.335	11
23301	965	826	5	26	13	11	11	11	55	\N	\N	45	6	00:01:42.475	11
23302	965	825	4	20	18	12	12	12	55	\N	\N	48	17	00:01:44.73	11
23303	965	835	4	30	15	13	13	13	55	\N	\N	18	16	00:01:44.724	11
23304	965	828	15	9	16	14	14	14	55	\N	\N	19	19	00:01:45.14	11
23305	965	831	15	12	21	15	15	15	55	\N	\N	55	13	00:01:44.117	11
23306	965	822	3	77	8	16	16	16	55	\N	\N	34	18	00:01:44.977	11
23307	965	836	209	94	20	17	17	17	55	\N	\N	36	21	00:01:45.451	11
23308	965	839	209	31	22	18	18	18	54	\N	\N	46	11	00:01:43.585	12
23309	965	8	6	7	5	\N	R	19	38	\N	\N	26	2	00:01:41.841	36
23310	965	830	9	33	4	\N	R	20	28	\N	\N	28	5	00:01:42.424	6
23311	965	821	210	21	14	\N	R	21	16	\N	\N	15	20	00:01:45.364	23
23312	965	807	10	27	7	\N	R	22	1	\N	\N	\N	0	\N	4
23313	966	1	131	44	1	1	1	1	71	1:40:31.402	6031402	66	4	00:01:22.596	1
23314	966	3	131	6	2	2	2	2	71	+8.354	6039756	43	5	00:01:22.792	1
23315	966	817	9	3	4	3	3	3	71	+20.858	6052260	53	1	00:01:21.134	1
23316	966	830	9	33	3	4	4	4	71	+21.323	6052725	66	6	00:01:22.887	1
23317	966	20	6	5	7	5	5	5	71	+27.313	6058715	61	2	00:01:22.497	1
23318	966	8	6	7	6	6	6	6	71	+49.376	6080778	47	3	00:01:22.512	1
23319	966	807	10	27	5	7	7	7	71	+58.891	6090293	50	9	00:01:23.288	1
23320	966	822	3	77	8	8	8	8	71	+1:05.612	6097014	65	11	00:01:23.54	1
23321	966	13	3	19	9	9	9	9	71	+1:16.206	6107608	64	12	00:01:23.576	1
23322	966	815	10	11	12	10	10	10	71	+1:16.798	6108200	62	13	00:01:23.607	1
23323	966	828	15	9	15	11	11	11	70	\N	\N	65	18	00:01:24.34	11
23324	966	18	1	22	13	12	12	12	70	\N	\N	70	17	00:01:23.777	11
23325	966	4	1	14	11	13	13	13	70	\N	\N	69	16	00:01:23.668	11
23326	966	835	4	30	21	14	14	14	70	\N	\N	64	20	00:01:24.574	11
23327	966	831	15	12	19	15	15	15	70	\N	\N	58	15	00:01:23.657	11
23328	966	832	5	55	10	16	16	16	70	\N	\N	52	19	00:01:24.467	11
23329	966	825	4	20	14	17	17	17	70	\N	\N	53	7	00:01:23.146	11
23330	966	826	5	26	18	18	18	18	70	\N	\N	59	14	00:01:23.618	11
23331	966	821	210	21	17	19	19	19	70	\N	\N	63	10	00:01:23.456	11
23332	966	154	210	8	22	20	20	20	70	\N	\N	53	8	00:01:23.278	11
23333	966	839	209	31	20	21	21	21	69	\N	\N	43	21	00:01:24.964	12
23335	967	1	131	44	1	1	1	1	71	3:01:01.335	10861335	44	3	00:01:25.639	1
23336	967	3	131	6	2	2	2	2	71	+11.455	10872790	47	6	00:01:26.222	1
23337	967	830	9	33	4	3	3	3	71	+21.481	10882816	67	1	00:01:25.305	1
23338	967	815	10	11	9	4	4	4	71	+25.346	10886681	41	11	00:01:27.093	1
23339	967	20	6	5	5	5	5	5	71	+26.334	10887669	70	5	00:01:26.195	1
23340	967	832	5	55	15	6	6	6	71	+29.160	10890495	38	13	00:01:27.153	1
23341	967	807	10	27	8	7	7	7	71	+29.827	10891162	69	8	00:01:26.728	1
23342	967	817	9	3	6	8	8	8	71	+30.486	10891821	42	2	00:01:25.532	1
23343	967	831	15	12	21	9	9	9	71	+42.620	10903955	70	15	00:01:27.547	1
23344	967	4	1	14	10	10	10	10	71	+44.432	10905767	70	12	00:01:27.104	1
23345	967	822	3	77	11	11	11	11	71	+45.292	10906627	70	4	00:01:26.062	1
23346	967	839	209	31	22	12	12	12	71	+45.809	10907144	47	16	00:01:27.796	1
23347	967	826	5	26	14	13	13	13	71	+51.192	10912527	42	14	00:01:27.476	1
23348	967	825	4	20	18	14	14	14	71	+51.555	10912890	69	7	00:01:26.524	1
23349	967	836	209	94	19	15	15	15	71	+1:00.498	10921833	69	18	00:01:27.919	1
23350	967	18	1	22	17	16	16	16	71	+1:21.994	10943329	38	10	00:01:26.983	1
23351	967	821	210	21	12	\N	R	17	60	\N	\N	43	17	00:01:27.805	31
23352	967	13	3	19	13	\N	R	18	46	\N	\N	39	9	00:01:26.767	4
23353	967	835	4	30	16	\N	R	19	20	\N	\N	11	21	00:01:34.334	130
23354	967	8	6	7	3	\N	R	20	19	\N	\N	12	19	00:01:28.847	4
23355	967	828	15	9	20	\N	R	21	11	\N	\N	11	20	00:01:31.265	4
23356	967	154	210	8	7	\N	W	22	0	\N	\N	\N	0	\N	54
23357	968	1	131	44	1	1	1	1	55	1:38:04.013	5884013	37	5	00:01:45.137	1
23358	968	3	131	6	2	2	2	2	55	+0.439	5884452	33	9	00:01:45.261	1
23359	968	20	6	5	5	3	3	3	55	+0.843	5884856	43	1	00:01:43.729	1
23360	968	830	9	33	6	4	4	4	55	+1.685	5885698	36	7	00:01:45.187	1
23361	968	817	9	3	3	5	5	5	55	+5.315	5889328	29	3	00:01:44.889	1
23362	968	8	6	7	4	6	6	6	55	+18.816	5902829	35	6	00:01:45.163	1
23363	968	807	10	27	7	7	7	7	55	+50.114	5934127	31	13	00:01:45.949	1
23364	968	815	10	11	8	8	8	8	55	+58.776	5942789	30	8	00:01:45.249	1
23365	968	13	3	19	10	9	9	9	55	+59.436	5943449	33	10	00:01:45.675	1
23366	968	4	1	14	9	10	10	10	55	+59.896	5943909	50	2	00:01:44.495	1
23367	968	154	210	8	14	11	11	11	55	+1:16.777	5960790	45	4	00:01:44.97	1
23368	968	821	210	21	13	12	12	12	55	+1:35.113	5979126	45	12	00:01:45.928	1
23369	968	839	209	31	20	13	13	13	54	\N	\N	46	15	00:01:46.189	11
23370	968	836	209	94	16	14	14	14	54	\N	\N	26	14	00:01:46.145	11
23371	968	828	15	9	22	15	15	15	54	\N	\N	40	16	00:01:46.216	11
23372	968	831	15	12	19	16	16	16	54	\N	\N	44	17	00:01:46.287	11
23373	968	835	4	30	15	17	17	17	54	\N	\N	46	11	00:01:45.715	11
23374	968	832	5	55	21	\N	R	18	41	\N	\N	30	18	00:01:46.591	130
23375	968	826	5	26	17	\N	R	19	14	\N	\N	13	21	00:01:48.752	6
23376	968	18	1	22	12	\N	R	20	12	\N	\N	4	22	00:01:48.753	22
23377	968	822	3	77	11	\N	R	21	6	\N	\N	4	19	00:01:47.837	22
23378	968	825	4	20	18	\N	R	22	5	\N	\N	4	20	00:01:48.601	22
23379	969	20	6	5	2	1	1	1	57	1:24:11.672	5051672	53	3	00:01:26.638	1
23380	969	1	131	44	1	2	2	2	57	+9.975	5061647	44	6	00:01:27.033	1
23381	969	822	131	77	3	3	3	3	57	+11.250	5062922	56	2	00:01:26.593	1
23382	969	8	6	7	4	4	4	4	57	+22.393	5074065	56	1	00:01:26.538	1
23383	969	830	9	33	5	5	5	5	57	+28.827	5080499	43	5	00:01:26.964	1
23384	969	13	3	19	7	6	6	6	57	+1:23.386	5135058	49	9	00:01:28.045	1
23385	969	815	10	11	10	7	7	7	56	\N	\N	56	10	00:01:28.336	11
23386	969	832	5	55	8	8	8	8	56	\N	\N	53	8	00:01:27.677	11
23387	969	826	5	26	9	9	9	9	56	\N	\N	51	4	00:01:26.711	11
23388	969	839	10	31	13	10	10	10	56	\N	\N	55	11	00:01:28.475	11
23389	969	807	4	27	11	11	11	11	56	\N	\N	55	12	00:01:28.486	11
23390	969	841	15	36	16	12	12	12	55	\N	\N	51	13	00:01:29.052	12
23391	969	838	1	2	18	13	13	13	55	\N	\N	53	15	00:01:29.44	12
23392	969	4	1	14	12	\N	R	14	50	\N	\N	48	17	00:01:30.077	76
23393	969	825	210	20	17	\N	R	15	46	\N	\N	46	7	00:01:27.568	22
23394	969	840	3	18	20	\N	R	16	40	\N	\N	38	14	00:01:29.389	23
23395	969	817	9	3	0	\N	R	17	25	\N	\N	21	16	00:01:29.447	131
23396	969	828	15	9	14	\N	R	18	21	\N	\N	18	19	00:01:32.052	9
23397	969	835	4	30	19	\N	R	19	15	\N	\N	6	20	00:01:32.195	23
23398	969	154	210	8	6	\N	R	20	13	\N	\N	12	18	00:01:30.183	47
23399	970	1	131	44	1	1	1	1	56	1:37:36.158	5856158	44	1	00:01:35.378	1
23400	970	20	6	5	2	2	2	2	56	+6.250	5862408	40	2	00:01:35.423	1
23401	970	830	9	33	16	3	3	3	56	+45.192	5901350	31	7	00:01:36.722	1
23402	970	817	9	3	5	4	4	4	56	+46.035	5902193	36	8	00:01:36.791	1
23403	970	8	6	7	4	5	5	5	56	+48.076	5904234	42	4	00:01:36.003	1
23404	970	822	131	77	3	6	6	6	56	+48.808	5904966	41	3	00:01:35.849	1
23405	970	832	5	55	11	7	7	7	56	+1:12.893	5929051	30	10	00:01:37.398	1
23406	970	825	210	20	12	8	8	8	55	\N	\N	35	11	00:01:37.528	11
23407	970	815	10	11	8	9	9	9	55	\N	\N	55	6	00:01:36.531	11
23408	970	839	10	31	17	10	10	10	55	\N	\N	55	9	00:01:37.036	11
23409	970	154	210	8	19	11	11	11	55	\N	\N	50	12	00:01:37.551	11
23410	970	807	4	27	7	12	12	12	55	\N	\N	36	13	00:01:38.015	11
23411	970	835	4	30	20	13	13	13	55	\N	\N	47	14	00:01:38.181	11
23412	970	13	3	19	6	14	14	14	55	\N	\N	50	5	00:01:36.511	11
23413	970	828	15	9	14	15	15	15	55	\N	\N	50	16	00:01:39.732	11
23414	970	4	1	14	13	\N	R	16	33	\N	\N	31	15	00:01:39.496	30
23415	970	826	5	26	9	\N	R	17	18	\N	\N	18	17	00:01:40.09	9
23416	970	838	1	2	15	\N	R	18	17	\N	\N	15	18	00:01:41.46	32
23417	970	841	15	36	18	\N	R	19	3	\N	\N	\N	0	\N	3
23418	970	840	3	18	10	\N	R	20	0	\N	\N	\N	0	\N	4
23419	971	20	6	5	3	1	1	1	57	1:33:53.374	5633374	36	4	00:01:33.826	1
23420	971	1	131	44	2	2	2	2	57	+6.660	5640034	46	1	00:01:32.798	1
23421	971	822	131	77	1	3	3	3	57	+20.397	5653771	33	5	00:01:34.087	1
23422	971	8	6	7	5	4	4	4	57	+22.475	5655849	55	3	00:01:33.72	1
23423	971	817	9	3	4	5	5	5	57	+39.346	5672720	42	2	00:01:33.495	1
23424	971	13	3	19	8	6	6	6	57	+54.326	5687700	39	6	00:01:34.256	1
23425	971	815	10	11	18	7	7	7	57	+1:02.606	5695980	39	7	00:01:34.609	1
23426	971	154	210	8	9	8	8	8	57	+1:14.865	5708239	33	8	00:01:34.948	1
23427	971	807	4	27	7	9	9	9	57	+1:20.188	5713562	40	12	00:01:35.372	1
23428	971	839	10	31	14	10	10	10	57	+1:35.711	5729085	39	11	00:01:35.179	1
23429	971	836	15	94	13	11	11	11	56	\N	\N	43	17	00:01:36.786	11
23430	971	826	5	26	11	12	12	12	56	\N	\N	45	9	00:01:34.985	11
23431	971	835	4	30	10	13	13	13	56	\N	\N	43	13	00:01:35.552	11
23432	971	4	1	14	15	14	14	14	54	\N	\N	47	14	00:01:35.595	131
23433	971	828	15	9	19	\N	R	15	50	\N	\N	35	10	00:01:35.086	6
23434	971	832	5	55	16	\N	R	16	12	\N	\N	8	18	00:01:38.026	4
23435	971	840	3	18	12	\N	R	17	12	\N	\N	10	15	00:01:36.303	4
23436	971	830	9	33	6	\N	R	18	11	\N	\N	4	16	00:01:36.681	23
23437	971	825	210	20	20	\N	R	19	8	\N	\N	6	19	00:01:38.718	10
23438	971	838	1	2	17	\N	R	20	0	\N	\N	\N	0	\N	131
23439	972	822	131	77	3	1	1	1	52	1:28:08.743	5288743	49	3	00:01:37.367	1
23440	972	20	6	5	1	2	2	2	52	+0.617	5289360	49	2	00:01:37.312	1
23441	972	8	6	7	2	3	3	3	52	+11.000	5299743	49	1	00:01:36.844	1
23442	972	1	131	44	4	4	4	4	52	+36.320	5325063	18	6	00:01:38.398	1
23443	972	830	9	33	7	5	5	5	52	+1:00.416	5349159	47	8	00:01:38.429	1
23444	972	815	10	11	9	6	6	6	52	+1:26.788	5375531	51	9	00:01:38.661	1
23445	972	839	10	31	10	7	7	7	52	+1:35.004	5383747	50	10	00:01:38.745	1
23446	972	807	4	27	8	8	8	8	52	+1:36.188	5384931	52	7	00:01:38.418	1
23447	972	13	3	19	6	9	9	9	51	\N	\N	45	4	00:01:38.232	11
23448	972	832	5	55	14	10	10	10	51	\N	\N	51	11	00:01:38.858	11
23449	972	840	3	18	11	11	11	11	51	\N	\N	50	12	00:01:38.87	11
23450	972	826	5	26	12	12	12	12	51	\N	\N	50	5	00:01:38.3	11
23451	972	825	210	20	13	13	13	13	51	\N	\N	40	13	00:01:39.566	11
23452	972	838	1	2	20	14	14	14	51	\N	\N	47	14	00:01:39.79	11
23453	972	828	15	9	18	15	15	15	51	\N	\N	48	15	00:01:39.835	11
23454	972	836	15	94	17	16	16	16	50	\N	\N	37	16	00:01:40.922	12
23455	972	817	9	3	5	\N	R	17	5	\N	\N	4	17	00:01:42.285	23
23456	972	835	4	30	16	\N	R	18	0	\N	\N	\N	0	\N	4
23457	972	154	210	8	19	\N	R	19	0	\N	\N	\N	0	\N	4
23458	972	4	1	14	15	\N	W	20	0	\N	\N	\N	0	\N	131
23459	973	1	131	44	1	1	1	1	66	1:35:56.497	5756497	64	1	00:01:23.593	1
23460	973	20	6	5	2	2	2	2	66	+3.490	5759987	43	2	00:01:23.674	1
23461	973	817	9	3	6	3	3	3	66	+1:15.820	5832317	40	3	00:01:23.686	1
23462	973	815	10	11	8	4	4	4	65	\N	\N	51	7	00:01:25.755	11
23463	973	839	10	31	10	5	5	5	65	\N	\N	40	11	00:01:26.276	11
23464	973	807	4	27	13	6	6	6	65	\N	\N	56	15	00:01:26.703	11
23465	973	832	5	55	12	7	7	7	65	\N	\N	61	9	00:01:26.186	11
23466	973	836	15	94	15	8	8	8	65	\N	\N	58	14	00:01:26.476	11
23467	973	826	5	26	19	9	9	9	65	\N	\N	37	8	00:01:25.976	11
23468	973	154	210	8	14	10	10	10	65	\N	\N	50	17	00:01:26.871	11
23469	973	828	15	9	16	11	11	11	64	\N	\N	60	10	00:01:26.213	12
23470	973	4	1	14	7	12	12	12	64	\N	\N	64	4	00:01:23.894	12
23471	973	13	3	19	9	13	13	13	64	\N	\N	64	13	00:01:26.472	12
23472	973	825	210	20	11	14	14	14	64	\N	\N	15	12	00:01:26.371	12
23473	973	835	4	30	17	15	15	15	64	\N	\N	44	6	00:01:24.843	12
23474	973	840	3	18	18	16	16	16	64	\N	\N	50	16	00:01:26.838	12
23475	973	822	131	77	3	\N	R	17	38	\N	\N	28	5	00:01:24.696	131
23476	973	838	1	2	20	\N	R	18	32	\N	\N	14	18	00:01:27.554	4
23477	973	830	9	33	5	\N	R	19	1	\N	\N	\N	0	\N	130
23478	973	8	6	7	4	\N	R	20	0	\N	\N	\N	0	\N	130
23479	974	20	6	5	2	1	1	1	78	1:44:44.340	6284340	38	2	00:01:15.238	1
23480	974	8	6	7	1	2	2	2	78	+3.145	6287485	39	3	00:01:15.527	1
23481	974	817	9	3	5	3	3	3	78	+3.745	6288085	51	4	00:01:15.756	1
23482	974	822	131	77	3	4	4	4	78	+5.517	6289857	22	9	00:01:16.439	1
23483	974	830	9	33	4	5	5	5	78	+6.199	6290539	56	8	00:01:16.329	1
23484	974	832	5	55	6	6	6	6	78	+12.038	6296378	39	14	00:01:16.649	1
23485	974	1	131	44	13	7	7	7	78	+15.801	6300141	54	5	00:01:15.825	1
23486	974	154	210	8	8	8	8	8	78	+18.150	6302490	45	18	00:01:17.095	1
23487	974	13	3	19	14	9	9	9	78	+19.445	6303785	50	12	00:01:16.543	1
23488	974	825	210	20	11	10	10	10	78	+21.443	6305783	44	7	00:01:16.313	1
23489	974	835	4	30	16	11	11	11	78	+22.737	6307077	55	13	00:01:16.614	1
23490	974	839	10	31	15	12	12	12	78	+23.725	6308065	52	10	00:01:16.482	1
23491	974	815	10	11	7	13	13	13	78	+39.089	6323429	76	1	00:01:14.82	1
23492	974	826	5	26	9	14	14	14	71	\N	\N	43	11	00:01:16.539	130
23493	974	840	3	18	17	15	15	15	71	\N	\N	71	6	00:01:16.075	23
23494	974	838	1	2	12	\N	R	16	66	\N	\N	45	15	00:01:16.665	3
23495	974	828	15	9	19	\N	R	17	63	\N	\N	39	16	00:01:16.829	3
23496	974	18	1	22	20	\N	R	18	57	\N	\N	47	17	00:01:16.912	130
23497	974	836	15	94	18	\N	R	19	57	\N	\N	25	20	00:01:18.034	4
23498	974	807	4	27	10	\N	R	20	15	\N	\N	13	19	00:01:17.885	6
23499	975	1	131	44	1	1	1	1	70	1:33:05.154	5585154	64	1	00:01:14.551	1
23500	975	822	131	77	3	2	2	2	70	+19.783	5604937	65	5	00:01:15.894	1
23501	975	817	9	3	6	3	3	3	70	+35.297	5620451	67	8	00:01:16.165	1
23502	975	20	6	5	2	4	4	4	70	+35.907	5621061	70	2	00:01:14.719	1
23503	975	815	10	11	8	5	5	5	70	+40.476	5625630	62	11	00:01:16.367	1
23504	975	839	10	31	9	6	6	6	70	+40.716	5625870	68	9	00:01:16.247	1
23505	975	8	6	7	4	7	7	7	70	+58.632	5643786	59	3	00:01:15.388	1
23506	975	807	4	27	10	8	8	8	70	+1:00.374	5645528	64	7	00:01:16.136	1
23507	975	840	3	18	17	9	9	9	69	\N	\N	64	6	00:01:15.979	11
23508	975	154	210	8	14	10	10	10	69	\N	\N	58	15	00:01:16.949	11
23509	975	835	4	30	15	11	11	11	69	\N	\N	64	12	00:01:16.704	11
23510	975	825	210	20	18	12	12	12	69	\N	\N	65	10	00:01:16.341	11
23511	975	828	15	9	19	13	13	13	69	\N	\N	50	16	00:01:16.995	11
23512	975	838	1	2	16	14	14	14	69	\N	\N	69	14	00:01:16.774	11
23513	975	836	15	94	20	15	15	15	68	\N	\N	66	17	00:01:17.091	12
23514	975	4	1	14	12	16	16	16	66	\N	\N	63	4	00:01:15.853	131
23515	975	826	5	26	11	\N	R	17	54	\N	\N	33	13	00:01:16.713	131
23516	975	830	9	33	5	\N	R	18	10	\N	\N	9	18	00:01:17.187	10
23517	975	13	3	19	7	\N	R	19	0	\N	\N	\N	0	\N	4
23519	976	817	9	3	10	1	1	1	51	2:03:55.573	7435573	46	4	00:01:44.882	1
23520	976	822	131	77	2	2	2	2	51	+3.904	7439477	51	3	00:01:43.925	1
23521	976	840	3	18	8	3	3	3	51	+4.009	7439582	44	5	00:01:45.108	1
23522	976	20	6	5	4	4	4	4	51	+5.976	7441549	47	1	00:01:43.441	1
23523	976	1	131	44	1	5	5	5	51	+6.188	7441761	46	2	00:01:43.469	1
23524	976	839	10	31	7	6	6	6	51	+30.298	7465871	39	9	00:01:45.634	1
23525	976	825	210	20	12	7	7	7	51	+41.753	7477326	45	11	00:01:46.312	1
23526	976	832	5	55	15	8	8	8	51	+49.400	7484973	46	10	00:01:45.866	1
23527	976	4	1	14	19	9	9	9	51	+59.551	7495124	49	6	00:01:45.168	1
23528	976	836	15	94	14	10	10	10	51	+1:29.093	7524666	46	15	00:01:47.12	1
23529	976	828	15	9	17	11	11	11	51	+1:31.794	7527367	45	16	00:01:47.186	1
23530	976	838	1	2	18	12	12	12	51	+1:32.160	7527733	45	13	00:01:46.648	1
23531	976	154	210	8	16	13	13	13	50	\N	\N	45	14	00:01:46.831	11
23532	976	8	6	7	3	14	14	14	46	\N	\N	44	7	00:01:45.542	34
23533	976	815	10	11	6	\N	R	15	39	\N	\N	37	8	00:01:45.588	136
23534	976	13	3	19	9	\N	R	16	25	\N	\N	10	17	00:01:47.34	22
23535	976	807	4	27	13	\N	R	17	24	\N	\N	9	19	00:01:48.536	3
23536	976	830	9	33	5	\N	R	18	12	\N	\N	10	12	00:01:46.398	51
23537	976	826	5	26	11	\N	R	19	9	\N	\N	9	18	00:01:48.394	84
23538	976	835	4	30	20	\N	R	20	7	\N	\N	5	20	00:01:51.673	131
23539	841	24	164	23	0	\N	F	23	0	\N	\N	\N	0	\N	81
23540	841	39	164	22	0	\N	F	24	0	\N	\N	\N	0	\N	81
23541	846	815	15	17	0	\N	W	24	0	\N	\N	\N	0	\N	82
23542	977	822	131	77	1	1	1	1	71	1:21:48.523	4908523	51	5	00:01:07.847	1
23543	977	20	6	5	2	2	2	2	71	+0.658	4909181	69	4	00:01:07.496	1
23544	977	817	9	3	4	3	3	3	71	+6.012	4914535	69	2	00:01:07.442	1
23545	977	1	131	44	8	4	4	4	71	+7.430	4915953	69	1	00:01:07.411	1
23546	977	8	6	7	3	5	5	5	71	+20.370	4928893	68	3	00:01:07.486	1
23547	977	154	210	8	6	6	6	6	71	+1:13.160	4981683	65	10	00:01:08.59	1
23548	977	815	10	11	7	7	7	7	70	\N	\N	58	9	00:01:08.47	11
23549	977	839	10	31	9	8	8	8	70	\N	\N	68	12	00:01:08.659	11
23550	977	13	3	19	17	9	9	9	70	\N	\N	49	7	00:01:08.419	11
23551	977	840	3	18	18	10	10	10	70	\N	\N	67	13	00:01:08.777	11
23552	977	835	4	30	16	11	11	11	70	\N	\N	64	11	00:01:08.652	11
23553	977	838	1	2	13	12	12	12	70	\N	\N	67	8	00:01:08.422	11
23554	977	807	4	27	11	13	13	13	70	\N	\N	64	14	00:01:09.043	11
23555	977	836	15	94	20	14	14	14	70	\N	\N	60	16	00:01:09.241	11
23556	977	828	15	9	19	15	15	15	69	\N	\N	56	17	00:01:09.284	12
23557	977	826	5	26	14	16	16	16	68	\N	\N	57	6	00:01:08.061	13
23558	977	832	5	55	10	\N	R	17	44	\N	\N	42	15	00:01:09.15	5
23559	977	825	210	20	15	\N	R	18	29	\N	\N	23	18	00:01:10.402	9
23560	977	4	1	14	12	\N	R	19	1	\N	\N	\N	0	\N	130
23561	977	830	9	33	5	\N	R	20	0	\N	\N	\N	0	\N	130
23562	978	1	131	44	1	1	1	1	51	1:21:27.430	4887430	48	1	00:01:30.621	1
23563	978	822	131	77	9	2	2	2	51	+14.063	4901493	46	3	00:01:30.905	1
23564	978	8	6	7	2	3	3	3	51	+36.570	4924000	44	4	00:01:31.517	1
23565	978	830	9	33	4	4	4	4	51	+52.125	4939555	51	2	00:01:30.678	1
23566	978	817	9	3	19	5	5	5	51	+1:05.955	4953385	47	6	00:01:31.874	1
23567	978	807	4	27	5	6	6	6	51	+1:08.109	4955539	43	8	00:01:32.577	1
23568	978	20	6	5	3	7	7	7	51	+1:33.989	4981419	38	5	00:01:31.872	1
23569	978	839	10	31	7	8	8	8	50	\N	\N	39	15	00:01:33.521	11
23570	978	815	10	11	6	9	9	9	50	\N	\N	42	14	00:01:33.504	11
23571	978	13	3	19	14	10	10	10	50	\N	\N	39	16	00:01:33.562	11
23572	978	838	1	2	8	11	11	11	50	\N	\N	43	13	00:01:33.464	11
23573	978	825	210	20	16	12	12	12	50	\N	\N	41	9	00:01:32.683	11
23574	978	154	210	8	10	13	13	13	50	\N	\N	45	7	00:01:32.29	11
23575	978	828	15	9	18	14	14	14	50	\N	\N	30	10	00:01:33.119	11
23576	978	826	5	26	12	15	15	15	50	\N	\N	29	17	00:01:33.594	11
23577	978	840	3	18	15	16	16	16	50	\N	\N	44	12	00:01:33.4	11
23578	978	836	15	94	17	17	17	17	50	\N	\N	34	11	00:01:33.342	11
23579	978	4	1	14	20	\N	R	18	32	\N	\N	22	18	00:01:34.263	131
23580	978	832	5	55	13	\N	R	19	0	\N	\N	\N	0	\N	130
23581	978	835	4	30	11	\N	R	20	0	\N	\N	\N	0	\N	9
23582	979	20	6	5	1	1	1	1	70	1:39:46.713	5986713	69	4	00:01:20.807	1
23583	979	8	6	7	2	2	2	2	70	+0.908	5987621	70	2	00:01:20.461	1
23584	979	822	131	77	3	3	3	3	70	+12.462	5999175	68	6	00:01:21.214	1
23585	979	1	131	44	4	4	4	4	70	+12.885	5999598	66	5	00:01:20.818	1
23586	979	830	9	33	5	5	5	5	70	+13.276	5999989	44	3	00:01:20.49	1
23587	979	4	1	14	7	6	6	6	70	+1:11.223	6057936	69	1	00:01:20.182	1
23588	979	832	5	55	9	7	7	7	69	\N	\N	67	11	00:01:21.871	11
23589	979	815	10	11	13	8	8	8	69	\N	\N	68	14	00:01:22.105	11
23590	979	839	10	31	11	9	9	9	69	\N	\N	60	15	00:01:22.431	11
23591	979	838	1	2	8	10	10	10	69	\N	\N	44	12	00:01:21.96	11
23592	979	826	5	26	16	11	11	11	69	\N	\N	42	9	00:01:21.631	11
23593	979	835	4	30	10	12	12	12	69	\N	\N	68	7	00:01:21.589	11
23594	979	825	210	20	15	13	13	13	69	\N	\N	67	13	00:01:22.1	11
23595	979	840	3	18	17	14	14	14	69	\N	\N	53	16	00:01:22.83	11
23596	979	836	15	94	18	15	15	15	68	\N	\N	50	18	00:01:23.573	12
23597	979	828	15	9	20	16	16	16	68	\N	\N	66	10	00:01:21.752	12
23598	979	807	4	27	12	17	17	17	67	\N	\N	61	8	00:01:21.611	23
23599	979	814	3	40	19	\N	R	18	60	\N	\N	49	17	00:01:23.242	44
23600	979	154	210	8	14	\N	R	19	20	\N	\N	19	19	00:01:24.702	61
23601	979	817	9	3	6	\N	R	20	0	\N	\N	\N	0	\N	4
23602	980	1	131	44	1	1	1	1	44	1:24:42.820	5082820	35	2	00:01:46.603	1
23603	980	20	6	5	2	2	2	2	44	+2.358	5085178	41	1	00:01:46.577	1
23604	980	817	9	3	6	3	3	3	44	+10.791	5093611	44	3	00:01:47.549	1
23605	980	8	6	7	4	4	4	4	44	+14.471	5097291	36	5	00:01:47.73	1
23606	980	822	131	77	3	5	5	5	44	+16.456	5099276	37	4	00:01:47.721	1
23607	980	807	4	27	7	6	6	6	44	+28.087	5110907	39	7	00:01:48.922	1
23608	980	154	210	8	11	7	7	7	44	+31.553	5114373	37	8	00:01:49.087	1
23609	980	13	3	19	16	8	8	8	44	+36.649	5119469	37	11	00:01:49.637	1
23610	980	839	10	31	9	9	9	9	44	+38.154	5120974	37	14	00:01:49.721	1
23611	980	832	5	55	13	10	10	10	44	+39.447	5122267	39	13	00:01:49.709	1
23612	980	840	3	18	15	11	11	11	44	+48.999	5131819	41	16	00:01:50.543	1
23613	980	826	5	26	19	12	12	12	44	+49.940	5132760	39	12	00:01:49.708	1
23614	980	835	4	30	14	13	13	13	44	+53.239	5136059	44	10	00:01:49.283	1
23615	980	838	1	2	20	14	14	14	44	+57.078	5139898	44	15	00:01:49.907	1
23616	980	825	210	20	12	15	15	15	44	+1:07.262	5150082	36	9	00:01:49.126	1
23617	980	828	15	9	17	16	16	16	44	+1:09.711	5152531	25	17	00:01:50.775	1
23618	980	815	10	11	8	17	17	17	42	\N	\N	27	6	00:01:48.3	6
23619	980	4	1	14	10	\N	R	18	25	\N	\N	12	19	00:01:51.72	5
23620	980	830	9	33	5	\N	R	19	7	\N	\N	5	18	00:01:51.022	5
23621	980	836	15	94	18	\N	R	20	2	\N	\N	\N	0	\N	4
23622	981	1	131	44	1	1	1	1	53	1:15:32.312	4532312	50	2	00:01:23.488	1
23623	981	822	131	77	4	2	2	2	53	+4.471	4536783	53	3	00:01:23.488	1
23624	981	20	6	5	6	3	3	3	53	+36.317	4568629	51	4	00:01:23.897	1
23625	981	817	9	3	16	4	4	4	53	+40.335	4572647	49	1	00:01:23.361	1
23626	981	8	6	7	5	5	5	5	53	+1:00.082	4592394	43	8	00:01:25.054	1
23627	981	839	10	31	3	6	6	6	53	+1:11.528	4603840	53	11	00:01:25.054	1
23628	981	840	3	18	2	7	7	7	53	+1:14.156	4606468	51	10	00:01:25.625	1
23629	981	13	3	19	7	8	8	8	53	+1:14.834	4607146	30	9	00:01:25.477	1
23630	981	815	10	11	10	9	9	9	53	+1:15.276	4607588	48	6	00:01:24.968	1
23631	981	830	9	33	13	10	10	10	52	\N	\N	48	5	00:01:24.351	11
23632	981	825	210	20	9	11	11	11	52	\N	\N	48	15	00:01:26.037	11
23633	981	826	5	26	8	12	12	12	52	\N	\N	43	14	00:01:25.894	11
23634	981	807	4	27	14	13	13	13	52	\N	\N	46	16	00:01:26.131	11
23635	981	832	5	55	15	14	14	14	52	\N	\N	46	17	00:01:26.21	11
23636	981	154	210	8	20	15	15	15	52	\N	\N	48	7	00:01:25.02	11
23637	981	836	15	94	12	16	16	16	51	\N	\N	47	18	00:01:26.547	12
23638	981	4	1	14	19	17	17	17	50	\N	\N	44	13	00:01:25.871	6
23639	981	828	15	9	11	18	18	18	49	\N	\N	20	20	00:01:27.663	6
23640	981	838	1	2	18	\N	R	19	33	\N	\N	30	19	00:01:26.912	5
23641	981	835	4	30	17	\N	R	20	29	\N	\N	27	12	00:01:25.752	5
23642	982	1	131	44	5	1	1	1	58	2:03:23.544	7403544	55	1	00:01:45.008	1
23643	982	817	9	3	3	2	2	2	58	+4.507	7408051	57	2	00:01:45.301	1
23644	982	822	131	77	6	3	3	3	58	+8.800	7412344	54	3	00:01:45.405	1
23645	982	832	5	55	10	4	4	4	58	+22.822	7426366	52	4	00:01:46.537	1
23646	982	815	10	11	12	5	5	5	58	+25.359	7428903	52	7	00:01:46.731	1
23647	982	835	4	30	11	6	6	6	58	+27.259	7430803	52	5	00:01:46.722	1
23648	982	838	1	2	9	7	7	7	58	+30.388	7433932	57	6	00:01:46.722	1
23649	982	840	3	18	18	8	8	8	58	+41.696	7445240	55	9	00:01:47.512	1
23650	982	154	210	8	15	9	9	9	58	+43.282	7446826	54	11	00:01:47.637	1
23651	982	839	10	31	14	10	10	10	58	+44.795	7448339	52	12	00:01:47.677	1
23652	982	13	3	19	17	11	11	11	58	+46.536	7450080	58	8	00:01:47.055	1
23653	982	836	15	94	19	12	12	12	56	\N	\N	56	14	00:01:49.061	12
23654	982	825	210	20	16	\N	R	13	50	\N	\N	44	10	00:01:47.585	5
23655	982	807	4	27	7	\N	R	14	48	\N	\N	37	13	00:01:48.011	5
23656	982	828	15	9	20	\N	R	15	35	\N	\N	35	15	00:01:52.496	3
23657	982	826	5	26	13	\N	R	16	10	\N	\N	10	16	00:02:10.512	3
23658	982	4	1	14	8	\N	R	17	8	\N	\N	6	17	00:02:13.579	130
23659	982	20	6	5	1	\N	R	18	0	\N	\N	\N	0	\N	3
23660	982	830	9	33	2	\N	R	19	0	\N	\N	\N	0	\N	3
23661	982	8	6	7	4	\N	R	20	0	\N	\N	\N	0	\N	3
23662	983	830	9	33	3	1	1	1	56	1:30:01.290	5401290	50	4	00:01:34.467	1
23663	983	1	131	44	1	2	2	2	56	+12.770	5414060	48	3	00:01:34.452	1
23664	983	817	9	3	4	3	3	3	56	+22.519	5423809	55	5	00:01:34.77	1
23665	983	20	6	5	20	4	4	4	56	+37.362	5438652	41	1	00:01:34.08	1
23666	983	822	131	77	5	5	5	5	56	+56.021	5457311	44	6	00:01:35.284	1
23667	983	815	10	11	9	6	6	6	56	+1:18.630	5479920	32	7	00:01:35.591	1
23668	983	838	1	2	7	7	7	7	55	\N	\N	49	9	00:01:35.931	11
23669	983	840	3	18	13	8	8	8	55	\N	\N	46	12	00:01:36.627	11
23670	983	13	3	19	11	9	9	9	55	\N	\N	44	14	00:01:36.944	11
23671	983	839	10	31	6	10	10	10	55	\N	\N	36	15	00:01:37.075	11
23672	983	4	1	14	10	11	11	11	55	\N	\N	11	11	00:01:36.501	11
23673	983	825	210	20	17	12	12	12	55	\N	\N	46	18	00:01:37.192	11
23674	983	154	210	8	16	13	13	13	55	\N	\N	49	8	00:01:35.796	11
23675	983	842	5	10	15	14	14	14	55	\N	\N	45	16	00:01:37.17	11
23676	983	835	4	30	12	15	15	15	55	\N	\N	45	17	00:01:37.186	11
23677	983	807	4	27	8	16	16	16	55	\N	\N	52	2	00:01:34.266	11
23678	983	836	15	94	18	17	17	17	55	\N	\N	53	10	00:01:36.395	11
23679	983	828	15	9	19	18	18	18	54	\N	\N	54	13	00:01:36.63	12
23680	983	832	5	55	14	\N	R	19	29	\N	\N	27	19	00:01:38.123	5
23681	983	8	6	7	0	\N	R	20	0	\N	\N	\N	0	\N	84
23682	984	1	131	44	1	1	1	1	53	1:27:31.194	5251194	43	6	00:01:33.78	1
23683	984	830	9	33	4	2	2	2	53	+1.211	5252405	51	5	00:01:33.73	1
23684	984	817	9	3	3	3	3	3	53	+9.679	5260873	52	3	00:01:33.694	1
23685	984	822	131	77	6	4	4	4	53	+10.580	5261774	50	1	00:01:33.144	1
23686	984	8	6	7	10	5	5	5	53	+32.622	5283816	50	2	00:01:33.175	1
23687	984	839	10	31	5	6	6	6	53	+1:07.788	5318982	50	11	00:01:34.843	1
23688	984	815	10	11	7	7	7	7	53	+1:11.424	5322618	23	10	00:01:34.744	1
23689	984	825	210	20	12	8	8	8	53	+1:28.953	5340147	50	13	00:01:35.338	1
23690	984	154	210	8	13	9	9	9	53	+1:29.883	5341077	50	14	00:01:35.347	1
23691	984	13	3	19	8	10	10	10	52	\N	\N	50	16	00:01:35.943	11
23692	984	4	1	14	20	11	11	11	52	\N	\N	45	12	00:01:35.111	11
23693	984	835	4	30	18	12	12	12	52	\N	\N	50	7	00:01:34.095	11
23694	984	842	5	10	14	13	13	13	52	\N	\N	45	8	00:01:34.533	11
23695	984	838	1	2	9	14	14	14	52	\N	\N	49	4	00:01:33.724	11
23696	984	836	15	94	17	15	15	15	51	\N	\N	27	17	00:01:36.43	12
23697	984	840	3	18	15	\N	R	16	45	\N	\N	37	9	00:01:34.548	36
23698	984	807	4	27	11	\N	R	17	40	\N	\N	28	15	00:01:35.883	33
23699	984	828	15	9	16	\N	R	18	7	\N	\N	7	18	00:01:38.596	3
23700	984	20	6	5	2	\N	R	19	4	\N	\N	2	19	00:02:06.457	105
23701	984	832	5	55	19	\N	R	20	0	\N	\N	\N	0	\N	3
23702	985	1	131	44	1	1	1	1	56	1:33:50.991	5630991	48	5	00:01:38.776	1
23703	985	20	6	5	2	2	2	2	56	+10.143	5641134	42	6	00:01:38.809	1
23704	985	8	6	7	5	3	3	3	56	+15.779	5646770	51	1	00:01:37.766	1
23705	985	830	9	33	16	4	4	4	56	+16.768	5647759	39	4	00:01:38.06	1
23706	985	822	131	77	3	5	5	5	56	+34.967	5665958	54	2	00:01:37.767	1
23707	985	839	10	31	6	6	6	6	56	+1:30.980	5721971	53	13	00:01:40.499	1
23708	985	832	4	55	7	7	7	7	56	+1:32.944	5723935	43	12	00:01:40.462	1
23709	985	815	10	11	9	8	8	8	55	\N	\N	14	14	00:01:40.851	11
23710	985	13	3	19	10	9	9	9	55	\N	\N	36	10	00:01:40.131	11
23711	985	826	5	26	11	10	10	10	55	\N	\N	19	15	00:01:40.971	11
23712	985	840	3	18	15	11	11	11	55	\N	\N	38	7	00:01:39.666	11
23713	985	838	1	2	20	12	12	12	55	\N	\N	27	11	00:01:40.349	11
23714	985	843	5	39	19	13	13	13	55	\N	\N	47	8	00:01:39.979	11
23715	985	154	210	8	12	14	14	14	55	\N	\N	36	17	00:01:41.259	11
23716	985	828	15	9	13	15	15	15	55	\N	\N	42	16	00:01:41.041	11
23717	985	825	210	20	17	16	16	16	55	\N	\N	51	3	00:01:37.893	11
23718	985	4	1	14	8	\N	R	17	24	\N	\N	21	18	00:01:41.537	5
23719	985	817	9	3	4	\N	R	18	14	\N	\N	14	9	00:01:40.102	5
23720	985	836	15	94	14	\N	R	19	5	\N	\N	2	20	00:01:47.073	4
23721	985	807	4	27	18	\N	R	20	3	\N	\N	2	19	00:01:44.27	5
23722	986	830	9	33	2	1	1	1	71	1:36:26.552	5786552	65	2	00:01:18.892	1
23723	986	822	131	77	4	2	2	2	71	+19.678	5806230	70	3	00:01:19.374	1
23724	986	8	6	7	5	3	3	3	71	+54.007	5840559	59	6	00:01:20.054	1
23725	986	20	6	5	1	4	4	4	71	+1:10.078	5856630	68	1	00:01:18.785	1
23726	986	839	10	31	6	5	5	5	70	\N	\N	67	9	00:01:20.946	11
23727	986	840	3	18	11	6	6	6	70	\N	\N	53	12	00:01:21.062	11
23728	986	815	10	11	9	7	7	7	70	\N	\N	54	4	00:01:19.929	11
23729	986	825	210	20	14	8	8	8	70	\N	\N	68	14	00:01:21.214	11
23730	986	1	131	44	3	9	9	9	70	\N	\N	69	5	00:01:19.945	11
23731	986	4	1	14	18	10	10	10	70	\N	\N	50	11	00:01:21.014	11
23732	986	13	3	19	10	11	11	11	70	\N	\N	55	13	00:01:21.136	11
23733	986	838	1	2	19	12	12	12	70	\N	\N	66	10	00:01:20.972	11
23734	986	842	5	10	20	13	13	13	70	\N	\N	70	8	00:01:20.859	11
23735	986	836	15	94	13	14	14	14	69	\N	\N	56	16	00:01:21.638	12
23736	986	154	210	8	15	15	15	15	69	\N	\N	64	7	00:01:20.345	12
23737	986	832	4	55	8	\N	R	16	59	\N	\N	34	15	00:01:21.36	5
23738	986	828	15	9	12	\N	R	17	55	\N	\N	54	17	00:01:21.686	5
23739	986	843	5	28	17	\N	R	18	30	\N	\N	28	19	00:01:22.572	5
23740	986	807	4	27	7	\N	R	19	24	\N	\N	18	18	00:01:21.691	10
23741	986	817	9	3	16	\N	R	20	5	\N	\N	4	20	00:01:22.789	5
23742	987	20	6	5	2	1	1	1	71	1:31:26.262	5486262	63	7	00:01:12.539	1
23743	987	822	131	77	1	2	2	2	71	+2.762	5489024	58	5	00:01:12.466	1
23744	987	8	6	7	3	3	3	3	71	+4.600	5490862	61	6	00:01:12.492	1
23745	987	1	131	44	20	4	4	4	71	+5.468	5491730	63	2	00:01:11.845	1
23746	987	830	9	33	4	5	5	5	71	+32.940	5519202	64	1	00:01:11.044	1
23747	987	817	9	3	14	6	6	6	71	+48.691	5534953	71	4	00:01:12.029	1
23748	987	13	3	19	9	7	7	7	71	+1:08.882	5555144	60	11	00:01:13.452	1
23749	987	4	1	14	6	8	8	8	71	+1:09.363	5555625	57	10	00:01:13.451	1
23750	987	815	10	11	5	9	9	9	71	+1:09.500	5555762	61	8	00:01:13.052	1
23751	987	807	4	27	7	10	10	10	70	\N	\N	57	15	00:01:13.758	11
23752	987	832	4	55	8	11	11	11	70	\N	\N	67	13	00:01:13.625	11
23753	987	842	5	10	19	12	12	12	70	\N	\N	61	9	00:01:13.323	11
23754	987	828	15	9	17	13	13	13	70	\N	\N	70	14	00:01:13.666	11
23755	987	836	15	94	15	14	14	14	70	\N	\N	60	17	00:01:14.812	11
23756	987	154	210	8	11	15	15	15	69	\N	\N	66	12	00:01:13.532	12
23757	987	840	3	18	16	16	16	16	69	\N	\N	69	3	00:01:11.862	12
23758	987	843	5	28	18	\N	R	17	40	\N	\N	29	16	00:01:14.658	5
23759	987	839	10	31	10	\N	R	18	0	\N	\N	\N	0	\N	3
23760	987	838	1	2	12	\N	R	19	0	\N	\N	\N	0	\N	3
23761	987	825	210	20	13	\N	R	20	0	\N	\N	\N	0	\N	3
23762	988	822	131	77	1	1	1	1	55	1:34:14.062	5654062	52	1	00:01:40.65	1
23763	988	1	131	44	2	2	2	2	55	+3.899	5657961	51	3	00:01:41.473	1
23764	988	20	6	5	3	3	3	3	55	+19.330	5673392	5	2	00:01:40.77	1
23765	988	8	6	7	5	4	4	4	55	+45.386	5699448	53	7	00:01:42.338	1
23766	988	830	9	33	6	5	5	5	55	+46.269	5700331	43	5	00:01:42.028	1
23767	988	807	4	27	7	6	6	6	55	+1:25.713	5739775	53	8	00:01:42.376	1
23768	988	815	10	11	8	7	7	7	55	+1:32.062	5746124	52	11	00:01:42.689	1
23769	988	839	10	31	9	8	8	8	55	+1:38.911	5752973	47	10	00:01:42.609	1
23770	988	4	1	14	11	9	9	9	54	\N	\N	26	4	00:01:43.378	11
23771	988	13	3	19	10	10	10	10	54	\N	\N	45	13	00:01:43.026	11
23772	988	154	210	8	16	11	11	11	54	\N	\N	51	9	00:01:42.437	11
23773	988	838	1	2	13	12	12	12	54	\N	\N	50	20	00:01:43.986	11
23774	988	825	210	20	14	13	13	13	54	\N	\N	50	19	00:01:43.928	11
23775	988	836	15	94	18	14	14	14	54	\N	\N	50	17	00:01:43.867	11
23776	988	843	5	28	20	15	15	15	54	\N	\N	52	18	00:01:43.897	11
23777	988	842	5	10	17	16	16	16	54	\N	\N	33	16	00:01:43.844	11
23778	988	828	15	9	19	17	17	17	54	\N	\N	36	15	00:01:43.567	11
23779	988	840	3	18	15	18	18	18	54	\N	\N	52	6	00:01:42.324	11
23780	988	832	4	55	12	\N	R	19	31	\N	\N	26	14	00:01:43.378	36
23781	988	817	9	3	4	\N	R	20	20	\N	\N	13	12	00:01:42.757	9
23782	989	20	6	5	3	1	1	1	58	1:29:33.283	5373283	53	4	00:01:26.469	1
23783	989	1	131	44	1	2	2	2	58	+5.036	5378319	50	3	00:01:26.444	1
23784	989	8	6	7	2	3	3	3	58	+6.309	5379592	57	2	00:01:26.373	1
23785	989	817	9	3	8	4	4	4	58	+7.069	5380352	54	1	00:01:25.945	1
23786	989	4	1	14	10	5	5	5	58	+27.886	5401169	57	7	00:01:26.978	1
23787	989	830	9	33	4	6	6	6	58	+28.945	5402228	54	5	00:01:26.88	1
23788	989	807	4	27	7	7	7	7	58	+32.671	5405954	57	9	00:01:27.081	1
23789	989	822	131	77	15	8	8	8	58	+34.339	5407622	54	8	00:01:27.019	1
23790	989	838	1	2	11	9	9	9	58	+34.921	5408204	57	6	00:01:26.958	1
23791	989	832	4	55	9	10	10	10	58	+45.722	5419005	51	12	00:01:27.944	1
23792	989	815	10	11	12	11	11	11	58	+46.817	5420100	51	11	00:01:27.633	1
23793	989	839	10	31	14	12	12	12	58	+1:00.278	5433561	57	10	00:01:27.6	1
23794	989	844	15	16	18	13	13	13	58	+1:15.759	5449042	56	15	00:01:28.759	1
23795	989	840	3	18	13	14	14	14	58	+1:18.288	5451571	55	14	00:01:28.511	1
23796	989	843	5	28	16	15	15	15	57	\N	\N	57	13	00:01:28.176	11
23797	989	154	210	8	6	\N	R	16	24	\N	\N	23	16	00:01:28.805	36
23798	989	825	210	20	5	\N	R	17	22	\N	\N	21	17	00:01:29.534	36
23799	989	842	5	10	20	\N	R	18	13	\N	\N	13	18	00:01:30.649	5
23800	989	828	15	9	17	\N	R	19	5	\N	\N	4	19	00:01:32.21	38
23801	989	845	3	35	19	\N	R	20	4	\N	\N	3	20	00:01:32.573	23
23802	990	20	6	5	1	1	1	1	57	1:32:01.940	5521940	21	7	00:01:34.453	1
23803	990	822	131	77	3	2	2	2	57	+0.699	5522639	22	1	00:01:33.74	1
23804	990	1	131	44	9	3	3	3	57	+6.512	5528452	51	2	00:01:33.953	1
23805	990	842	5	10	5	4	4	4	57	+1:02.234	5584174	46	11	00:01:34.863	1
23806	990	825	210	20	6	5	5	5	57	+1:15.046	5596986	29	5	00:01:34.327	1
23807	990	807	4	27	7	6	6	6	57	+1:39.024	5620964	50	9	00:01:34.667	1
23808	990	4	1	14	13	7	7	7	56	\N	\N	47	4	00:01:34.168	11
23809	990	838	1	2	14	8	8	8	56	\N	\N	30	16	00:01:35.131	11
23810	990	828	15	9	17	9	9	9	56	\N	\N	26	15	00:01:35.093	11
23811	990	839	10	31	8	10	10	10	56	\N	\N	38	12	00:01:35.043	11
23812	990	832	4	55	10	11	11	11	56	\N	\N	35	18	00:01:35.535	11
23813	990	844	15	16	19	12	12	12	56	\N	\N	35	14	00:01:35.075	11
23814	990	154	210	8	16	13	13	13	56	\N	\N	44	10	00:01:34.689	11
23815	990	840	3	18	20	14	14	14	56	\N	\N	40	13	00:01:35.058	11
23816	990	845	3	35	18	15	15	15	56	\N	\N	47	3	00:01:34.053	11
23817	990	815	10	11	12	16	16	16	56	\N	\N	32	17	00:01:35.266	11
23818	990	843	5	28	11	17	17	17	56	\N	\N	42	8	00:01:34.563	11
23819	990	8	6	7	2	\N	R	18	35	\N	\N	22	6	00:01:34.337	36
23820	990	830	9	33	15	\N	R	19	3	\N	\N	\N	0	\N	29
23821	990	817	9	3	4	\N	R	20	1	\N	\N	\N	0	\N	10
23822	991	817	9	3	6	1	1	1	56	1:35:36.380	5736380	55	1	00:01:35.785	1
23823	991	822	131	77	3	2	2	2	56	+8.894	5745274	50	6	00:01:36.987	1
23824	991	8	6	7	2	3	3	3	56	+9.637	5746017	48	3	00:01:36.456	1
23825	991	1	131	44	4	4	4	4	56	+16.985	5753365	20	4	00:01:36.878	1
23826	991	830	9	33	5	5	5	5	56	+20.436	5756816	50	2	00:01:36.206	1
23827	991	807	4	27	7	6	6	6	56	+21.052	5757432	56	5	00:01:36.881	1
23828	991	4	1	14	13	7	7	7	56	+30.639	5767019	56	7	00:01:37.234	1
23829	991	20	6	5	1	8	8	8	56	+35.286	5771666	24	9	00:01:37.479	1
23830	991	832	4	55	9	9	9	9	56	+35.763	5772143	54	11	00:01:37.754	1
23831	991	825	210	20	11	10	10	10	56	+39.594	5775974	54	14	00:01:38.152	1
23832	991	839	10	31	12	11	11	11	56	+44.050	5780430	47	12	00:01:37.985	1
23833	991	815	10	11	8	12	12	12	56	+44.725	5781105	54	10	00:01:37.673	1
23834	991	838	1	2	14	13	13	13	56	+49.373	5785753	54	13	00:01:38.137	1
23835	991	840	3	18	18	14	14	14	56	+55.490	5791870	54	17	00:01:38.5	1
23836	991	845	3	35	16	15	15	15	56	+58.241	5794621	47	18	00:01:38.624	1
23837	991	828	15	9	20	16	16	16	56	+1:02.604	5798984	52	16	00:01:38.386	1
23838	991	154	210	8	10	17	17	17	56	+1:05.296	5801676	51	8	00:01:37.41	1
23839	991	842	5	10	17	18	18	18	56	+1:06.330	5802710	54	15	00:01:38.367	1
23840	991	844	15	16	19	19	19	19	56	+1:22.575	5818955	23	19	00:01:38.808	1
23841	991	843	5	28	15	20	20	20	51	\N	\N	50	20	00:01:39.376	130
23842	992	1	131	44	2	1	1	1	51	1:43:44.291	6224291	35	2	00:01:45.412	1
23843	992	8	6	7	6	2	2	2	51	+2.460	6226751	50	7	00:01:46.523	1
23844	992	815	10	11	8	3	3	3	51	+4.024	6228315	51	6	00:01:46.206	1
23845	992	20	6	5	1	4	4	4	51	+5.329	6229620	38	4	00:01:45.53	1
23846	992	832	4	55	9	5	5	5	51	+7.515	6231806	50	9	00:01:46.856	1
23847	992	844	15	16	13	6	6	6	51	+9.158	6233449	31	11	00:01:47.403	1
23848	992	4	1	14	12	7	7	7	51	+10.931	6235222	32	12	00:01:47.449	1
23849	992	840	3	18	10	8	8	8	51	+12.546	6236837	50	8	00:01:46.815	1
23850	992	838	1	2	16	9	9	9	51	+14.152	6238443	50	13	00:01:47.666	1
23851	992	843	5	28	19	10	10	10	51	+18.030	6242321	51	17	00:01:48.288	1
23852	992	828	15	9	18	11	11	11	51	+18.512	6242803	51	14	00:01:47.925	1
23853	992	842	5	10	17	12	12	12	51	+24.720	6249011	38	15	00:01:48.035	1
23854	992	825	210	20	15	13	13	13	51	+40.663	6264954	35	16	00:01:48.155	1
23855	992	822	131	77	3	\N	R	14	48	\N	\N	37	1	00:01:45.149	29
23856	992	154	210	8	20	\N	R	15	42	\N	\N	34	10	00:01:46.88	3
23857	992	830	9	33	5	\N	R	16	39	\N	\N	31	5	00:01:45.771	4
23858	992	817	9	3	4	\N	R	17	39	\N	\N	34	3	00:01:45.419	4
23859	992	807	4	27	14	\N	R	18	10	\N	\N	10	18	00:01:48.867	3
23860	992	839	10	31	7	\N	R	19	0	\N	\N	\N	0	\N	4
23861	992	845	3	35	11	\N	R	20	0	\N	\N	\N	0	\N	4
23862	993	1	131	44	1	1	1	1	66	1:35:29.972	5729972	64	3	00:01:19.133	1
23863	993	822	131	77	2	2	2	2	66	+20.593	5750565	56	5	00:01:19.478	1
23864	993	830	9	33	5	3	3	3	66	+26.873	5756845	62	4	00:01:19.422	1
23865	993	20	6	5	3	4	4	4	66	+27.584	5757556	61	2	00:01:19.128	1
23866	993	817	9	3	6	5	5	5	66	+50.058	5780030	61	1	00:01:18.441	1
23867	993	825	210	20	7	6	6	6	65	\N	\N	64	6	00:01:20.246	11
23868	993	832	4	55	9	7	7	7	65	\N	\N	61	9	00:01:21.324	11
23869	993	4	1	14	8	8	8	8	65	\N	\N	64	7	00:01:20.727	11
23870	993	815	10	11	15	9	9	9	64	\N	\N	43	8	00:01:21.128	12
23871	993	844	15	16	14	10	10	10	64	\N	\N	51	14	00:01:22.122	12
23872	993	840	3	18	18	11	11	11	64	\N	\N	60	12	00:01:22.095	12
23873	993	843	5	28	20	12	12	12	64	\N	\N	63	10	00:01:21.439	12
23874	993	828	15	9	17	13	13	13	64	\N	\N	50	15	00:01:22.487	12
23875	993	845	3	35	19	14	14	14	63	\N	\N	57	17	00:01:22.68	13
23876	993	838	1	2	11	\N	R	15	45	\N	\N	38	16	00:01:22.594	6
23877	993	839	10	31	13	\N	R	16	38	\N	\N	36	13	00:01:22.117	44
23878	993	8	6	7	4	\N	R	17	25	\N	\N	23	11	00:01:21.531	101
23879	993	154	210	8	10	\N	R	18	0	\N	\N	\N	0	\N	4
23880	993	842	5	10	12	\N	R	19	0	\N	\N	\N	0	\N	4
23881	993	807	4	27	16	\N	R	20	0	\N	\N	\N	0	\N	4
23882	994	817	9	3	1	1	1	1	78	1:42:54.807	6174807	13	5	00:01:15.562	1
23883	994	20	6	5	2	2	2	2	78	+7.336	6182143	14	7	00:01:16.065	1
23884	994	1	131	44	3	3	3	3	78	+17.013	6191820	15	8	00:01:16.27	1
23885	994	8	6	7	4	4	4	4	78	+18.127	6192934	13	10	00:01:16.392	1
23886	994	822	131	77	5	5	5	5	78	+18.822	6193629	21	9	00:01:16.312	1
23887	994	839	10	31	6	6	6	6	78	+23.667	6198474	63	14	00:01:17.027	1
23888	994	842	5	10	10	7	7	7	78	+24.331	6199138	68	15	00:01:17.099	1
23889	994	807	4	27	11	8	8	8	78	+24.839	6199646	57	6	00:01:16.061	1
23890	994	830	9	33	20	9	9	9	78	+25.317	6200124	60	1	00:01:14.26	1
23891	994	832	4	55	8	10	10	10	78	+1:09.013	6243820	19	18	00:01:17.491	1
23892	994	828	15	9	16	11	11	11	78	+1:09.864	6244671	19	12	00:01:16.936	1
23893	994	815	10	11	9	12	12	12	78	+1:10.461	6245268	24	19	00:01:17.546	1
23894	994	825	210	20	19	13	13	13	78	+1:14.823	6249630	20	17	00:01:17.476	1
23895	994	838	1	2	12	14	14	14	77	\N	\N	76	11	00:01:16.864	11
23896	994	154	210	8	18	15	15	15	77	\N	\N	74	2	00:01:14.822	11
23897	994	845	3	35	13	16	16	16	77	\N	\N	75	4	00:01:15.325	11
23898	994	840	3	18	17	17	17	17	76	\N	\N	61	3	00:01:14.944	12
23899	994	844	15	16	14	\N	R	18	70	\N	\N	17	20	00:01:17.71	4
23900	994	843	5	28	15	\N	R	19	70	\N	\N	15	16	00:01:17.172	4
23901	994	4	1	14	7	\N	R	20	52	\N	\N	23	13	00:01:17.018	6
23902	995	20	6	5	1	1	1	1	68	1:28:31.377	5311377	57	2	00:01:13.964	1
23903	995	822	131	77	2	2	2	2	68	+7.376	5318753	51	3	00:01:13.992	1
23904	995	830	9	33	3	3	3	3	68	+8.360	5319737	65	1	00:01:13.864	1
23905	995	817	9	3	6	4	4	4	68	+20.892	5332269	59	5	00:01:14.159	1
23906	995	1	131	44	4	5	5	5	68	+21.559	5332936	66	6	00:01:14.183	1
23907	995	8	6	7	5	6	6	6	68	+27.184	5338561	59	4	00:01:14.075	1
23908	995	807	4	27	7	7	7	7	67	\N	\N	64	11	00:01:15.588	11
23909	995	832	4	55	9	8	8	8	67	\N	\N	61	13	00:01:15.666	11
23910	995	839	10	31	8	9	9	9	67	\N	\N	61	12	00:01:15.61	11
23911	995	844	15	16	13	10	10	10	67	\N	\N	65	10	00:01:15.48	11
23912	995	842	5	10	16	11	11	11	67	\N	\N	67	14	00:01:15.699	11
23913	995	154	210	8	20	12	12	12	67	\N	\N	56	9	00:01:15.47	11
23914	995	825	210	20	11	13	13	13	67	\N	\N	65	8	00:01:15.401	11
23915	995	815	10	11	10	14	14	14	67	\N	\N	64	7	00:01:15.1	11
23916	995	828	15	9	19	15	15	15	66	\N	\N	62	18	00:01:16.403	12
23917	995	838	1	2	15	16	16	16	66	\N	\N	55	15	00:01:15.765	12
23918	995	845	3	35	18	17	17	17	66	\N	\N	53	16	00:01:15.924	12
23919	995	4	1	14	14	\N	R	18	40	\N	\N	33	17	00:01:16.18	43
23920	995	843	5	28	12	\N	R	19	0	\N	\N	\N	0	\N	4
23921	995	840	3	18	17	\N	R	20	0	\N	\N	\N	0	\N	4
23922	996	1	131	44	1	1	1	1	53	1:30:11.385	5411385	49	5	00:01:34.509	1
23923	996	830	9	33	4	2	2	2	53	+7.090	5418475	47	2	00:01:34.275	1
23924	996	8	6	7	6	3	3	3	53	+25.888	5437273	48	3	00:01:34.398	1
23925	996	817	9	3	5	4	4	4	53	+34.736	5446121	37	7	00:01:35.382	1
23926	996	20	6	5	3	5	5	5	53	+1:01.935	5473320	42	4	00:01:34.485	1
23927	996	825	210	20	9	6	6	6	53	+1:19.364	5490749	50	8	00:01:35.425	1
23928	996	822	131	77	2	7	7	7	53	+1:20.632	5492017	41	1	00:01:34.225	1
23929	996	832	4	55	7	8	8	8	53	+1:27.184	5498569	46	9	00:01:35.638	1
23930	996	807	4	27	12	9	9	9	53	+1:31.989	5503374	46	11	00:01:35.873	1
23931	996	844	15	16	8	10	10	10	53	+1:33.873	5505258	45	12	00:01:35.977	1
23932	996	154	210	8	10	11	11	11	52	\N	\N	47	10	00:01:35.695	11
23933	996	838	1	2	17	12	12	12	52	\N	\N	48	14	00:01:36.675	11
23934	996	828	15	9	15	13	13	13	52	\N	\N	37	13	00:01:36.494	11
23935	996	843	5	28	20	14	14	14	52	\N	\N	40	15	00:01:36.839	11
23936	996	845	3	35	18	15	15	15	52	\N	\N	35	16	00:01:38.3	11
23937	996	4	1	14	16	16	16	16	50	\N	\N	48	6	00:01:35.133	36
23938	996	840	3	18	19	17	17	17	48	\N	\N	35	18	00:01:38.319	29
23939	996	815	10	11	13	\N	R	18	27	\N	\N	25	17	00:01:38.319	5
23940	996	839	10	31	11	\N	R	19	0	\N	\N	\N	0	\N	4
23941	996	842	5	10	14	\N	R	20	0	\N	\N	\N	0	\N	4
23942	997	830	9	33	4	1	1	1	71	1:21:56.024	4916024	70	4	00:01:07.442	1
23943	997	8	6	7	3	2	2	2	71	+1.504	4917528	71	1	00:01:06.957	1
23944	997	20	6	5	6	3	3	3	71	+3.181	4919205	67	2	00:01:07.082	1
23945	997	154	210	8	5	4	4	4	70	\N	\N	17	16	00:01:09.071	11
23946	997	825	210	20	8	5	5	5	70	\N	\N	70	7	00:01:08.476	11
23947	997	839	10	31	11	6	6	6	70	\N	\N	64	11	00:01:08.85	11
23948	997	815	10	11	16	7	7	7	70	\N	\N	66	8	00:01:08.504	11
23949	997	4	1	14	13	8	8	8	70	\N	\N	69	9	00:01:08.661	11
23950	997	844	15	16	18	9	9	9	70	\N	\N	68	14	00:01:09.006	11
23951	997	828	15	9	20	10	10	10	70	\N	\N	67	6	00:01:08.216	11
23952	997	842	5	10	12	11	11	11	70	\N	\N	38	19	00:01:09.295	11
23953	997	832	4	55	9	12	12	12	70	\N	\N	37	10	00:01:08.766	11
23954	997	845	3	35	17	13	13	13	69	\N	\N	64	13	00:01:08.971	12
23955	997	840	3	18	14	14	14	14	69	\N	\N	68	18	00:01:09.203	12
23956	997	838	1	2	15	15	15	15	65	\N	\N	63	12	00:01:08.894	130
23957	997	1	131	44	2	\N	R	16	62	\N	\N	58	3	00:01:07.241	32
23958	997	843	5	28	19	\N	R	17	54	\N	\N	42	17	00:01:09.171	9
23959	997	817	9	3	7	\N	R	18	53	\N	\N	46	5	00:01:07.591	43
23960	997	822	131	77	1	\N	R	19	13	\N	\N	12	15	00:01:09.044	9
23961	997	807	4	27	10	\N	R	20	11	\N	\N	7	20	00:01:10.38	5
23962	998	20	6	5	2	1	1	1	52	1:27:29.784	5249784	47	1	00:01:30.696	1
23963	998	1	131	44	1	2	2	2	52	+2.264	5252048	52	3	00:01:31.245	1
23964	998	8	6	7	3	3	3	3	52	+3.652	5253436	51	2	00:01:30.795	1
23965	998	822	131	77	4	4	4	4	52	+8.883	5258667	43	4	00:01:31.377	1
23966	998	817	9	3	6	5	5	5	52	+9.500	5259284	46	5	00:01:31.589	1
23967	998	807	4	27	11	6	6	6	52	+28.220	5278004	48	7	00:01:33.405	1
23968	998	839	10	31	10	7	7	7	52	+29.930	5279714	48	13	00:01:33.606	1
23969	998	4	1	14	13	8	8	8	52	+31.115	5280899	52	10	00:01:33.482	1
23970	998	825	210	20	7	9	9	9	52	+33.188	5282972	48	12	00:01:33.604	1
23971	998	815	10	11	12	10	10	10	52	+34.708	5284492	48	9	00:01:33.472	1
23972	998	838	1	2	17	11	11	11	52	+35.774	5285558	48	11	00:01:33.551	1
23973	998	840	3	18	19	12	12	12	52	+38.106	5287890	48	15	00:01:33.869	1
23974	998	842	5	10	14	13	13	13	52	+39.129	5288913	48	8	00:01:33.465	1
23975	998	845	3	35	18	14	14	14	52	+48.113	5297897	52	18	00:01:34.62	1
23982	998	843	5	28	0	\N	R	20	1	\N	\N	\N	0	\N	131
23977	998	830	9	33	5	\N	R	15	46	\N	\N	42	6	00:01:32.007	23
23978	998	154	210	8	8	\N	R	16	37	\N	\N	28	16	00:01:34.391	4
23979	998	832	4	55	16	\N	R	17	37	\N	\N	25	17	00:01:34.602	4
23980	998	828	15	9	15	\N	R	18	31	\N	\N	26	14	00:01:33.675	3
23981	998	844	15	16	9	\N	R	19	18	\N	\N	3	19	00:01:35.209	27
23983	999	1	131	44	14	1	1	1	67	1:32:29.845	5549845	66	1	00:01:15.545	1
23984	999	822	131	77	2	2	2	2	67	+4.535	5554380	65	2	00:01:15.721	1
23985	999	8	6	7	3	3	3	3	67	+6.732	5556577	64	4	00:01:15.99	1
23986	999	830	9	33	4	4	4	4	67	+7.654	5557499	66	3	00:01:15.852	1
23987	999	807	4	27	7	5	5	5	67	+26.609	5576454	66	16	00:01:17.91	1
23988	999	154	210	8	6	6	6	6	67	+28.871	5578716	66	5	00:01:16.716	1
23989	999	815	10	11	10	7	7	7	67	+30.556	5580401	66	15	00:01:17.867	1
23990	999	839	10	31	15	8	8	8	67	+31.750	5581595	64	17	00:01:17.941	1
23991	999	828	15	9	13	9	9	9	67	+32.362	5582207	65	12	00:01:17.745	1
23992	999	843	5	28	17	10	10	10	67	+34.197	5584042	66	9	00:01:17.681	1
23993	999	825	210	20	5	11	11	11	67	+34.919	5584764	66	10	00:01:17.697	1
23994	999	832	4	55	8	12	12	12	67	+43.069	5592914	63	7	00:01:17.43	1
23995	999	838	1	2	19	13	13	13	67	+46.617	5596462	67	8	00:01:17.537	1
23996	999	842	5	10	16	14	14	14	66	\N	\N	66	13	00:01:17.762	11
23997	999	844	15	16	9	15	15	15	66	\N	\N	64	14	00:01:17.852	11
23998	999	4	1	14	11	16	16	16	65	\N	\N	60	11	00:01:17.741	31
23999	999	840	3	18	18	\N	R	17	53	\N	\N	35	19	00:01:18.861	5
24000	999	20	6	5	1	\N	R	18	51	\N	\N	39	6	00:01:17.29	3
24001	999	845	3	35	12	\N	R	19	51	\N	\N	36	20	00:01:18.934	5
24002	999	817	9	3	20	\N	R	20	27	\N	\N	22	18	00:01:18.262	5
24003	1000	1	131	44	1	1	1	1	70	1:37:16.427	5836427	63	4	00:01:21.107	1
24004	1000	20	6	5	4	2	2	2	70	+17.123	5853550	70	2	00:01:20.056	1
24005	1000	8	6	7	3	3	3	3	70	+20.101	5856528	55	3	00:01:20.292	1
24006	1000	817	9	3	12	4	4	4	70	+46.419	5882846	46	1	00:01:20.012	1
24007	1000	822	131	77	2	5	5	5	70	+50.000	5886427	39	8	00:01:21.736	1
24008	1000	842	5	10	6	6	6	6	70	+1:13.273	5909700	64	7	00:01:21.685	1
24009	1000	825	210	20	9	7	7	7	69	\N	\N	60	6	00:01:21.302	11
24010	1000	4	1	14	11	8	8	8	69	\N	\N	68	9	00:01:22.09	11
24011	1000	832	4	55	5	9	9	9	69	\N	\N	58	13	00:01:22.774	11
24012	1000	154	210	8	10	10	10	10	69	\N	\N	58	10	00:01:22.606	11
24013	1000	843	5	28	8	11	11	11	69	\N	\N	62	11	00:01:22.612	11
24014	1000	807	4	27	13	12	12	12	69	\N	\N	69	5	00:01:21.261	11
24015	1000	839	10	31	18	13	13	13	69	\N	\N	63	14	00:01:22.876	11
24016	1000	815	10	11	19	14	14	14	69	\N	\N	56	16	00:01:23.263	11
24017	1000	828	15	9	14	15	15	15	68	\N	\N	53	17	00:01:23.671	12
24018	1000	845	3	35	20	16	16	16	68	\N	\N	53	18	00:01:23.708	12
24019	1000	840	3	18	15	17	17	17	68	\N	\N	51	12	00:01:22.66	12
24020	1000	838	1	2	16	\N	R	18	49	\N	\N	46	15	00:01:23.077	6
24021	1000	830	9	33	7	\N	R	19	5	\N	\N	5	19	00:01:23.985	75
24022	1000	844	15	16	17	\N	R	20	0	\N	\N	\N	0	\N	22
24023	1001	20	6	5	2	1	1	1	44	1:23:34.476	5014476	25	2	00:01:46.644	1
24024	1001	1	131	44	1	2	2	2	44	+11.061	5025537	23	3	00:01:46.721	1
24025	1001	830	9	33	7	3	3	3	44	+31.372	5045848	36	4	00:01:46.946	1
24026	1001	822	131	77	19	4	4	4	44	+1:03.605	5078081	32	1	00:01:46.286	1
24027	1001	815	10	11	4	5	5	5	44	+1:11.023	5085499	38	7	00:01:48.08	1
24028	1001	839	10	31	3	6	6	6	44	+1:19.520	5093996	35	6	00:01:48.078	1
24029	1001	154	210	8	5	7	7	7	44	+1:25.953	5100429	35	8	00:01:48.283	1
24030	1001	825	210	20	9	8	8	8	44	+1:27.639	5102115	36	5	00:01:47.937	1
24031	1001	842	5	10	10	9	9	9	44	+1:45.892	5120368	36	9	00:01:48.588	1
24032	1001	828	15	9	13	10	10	10	43	\N	\N	35	11	00:01:48.694	11
24033	1001	832	4	55	14	11	11	11	43	\N	\N	32	10	00:01:48.67	11
24034	1001	845	3	35	16	12	12	12	43	\N	\N	42	14	00:01:49.113	11
24035	1001	840	3	18	17	13	13	13	43	\N	\N	39	16	00:01:49.287	11
24036	1001	843	5	28	11	14	14	14	43	\N	\N	33	12	00:01:48.756	11
24037	1001	838	1	2	18	15	15	15	43	\N	\N	38	13	00:01:48.956	11
24038	1001	817	9	3	8	\N	R	16	28	\N	\N	27	15	00:01:49.242	31
24039	1001	8	6	7	6	\N	R	17	8	\N	\N	6	17	00:01:54.32	23
24040	1001	844	15	16	12	\N	R	18	0	\N	\N	\N	0	\N	3
24041	1001	4	1	14	15	\N	R	19	0	\N	\N	\N	0	\N	3
24042	1001	807	4	27	20	\N	R	20	0	\N	\N	\N	0	\N	3
24043	1002	1	131	44	3	1	1	1	53	1:16:54.484	4614484	30	1	00:01:22.497	1
24044	1002	8	6	7	1	2	2	2	53	+8.705	4623189	28	4	00:01:23.515	1
24045	1002	822	131	77	4	3	3	3	53	+14.066	4628550	39	3	00:01:22.907	1
24046	1002	20	6	5	2	4	4	4	53	+16.151	4630635	51	2	00:01:22.505	1
24047	1002	830	9	33	5	5	5	5	53	+18.208	4632692	41	6	00:01:23.609	1
24048	1002	839	10	31	8	7	7	6	53	+57.761	4672245	48	12	00:01:24.243	1
24049	1002	815	10	11	14	8	8	7	53	+58.678	4673162	44	11	00:01:24.179	1
24050	1002	832	4	55	7	9	9	8	53	+1:18.140	4692624	43	5	00:01:23.529	1
24051	1002	840	3	18	10	10	10	9	52	\N	\N	52	9	00:01:24.056	11
24052	1002	845	3	35	12	11	11	10	52	\N	\N	39	14	00:01:24.58	11
24053	1002	844	15	16	15	12	12	11	52	\N	\N	52	8	00:01:23.768	11
24054	1002	838	1	2	17	13	13	12	52	\N	\N	52	13	00:01:24.504	11
24055	1002	807	4	27	20	14	14	13	52	\N	\N	47	16	00:01:24.772	11
24056	1002	842	5	10	9	15	15	14	52	\N	\N	47	10	00:01:24.059	11
24057	1002	828	15	9	18	16	16	15	52	\N	\N	46	15	00:01:24.767	11
24058	1002	825	210	20	11	17	17	16	52	\N	\N	44	7	00:01:23.768	11
24059	1002	817	9	3	19	\N	R	17	23	\N	\N	46	18	00:01:25.692	5
24060	1002	4	1	14	13	\N	R	18	9	\N	\N	18	17	00:01:25.229	5
24061	1002	843	5	28	16	\N	R	19	0	\N	\N	6	19	00:01:27.009	23
24062	1002	154	210	8	6	\N	D	20	53	+56.320	4670804	\N	0	\N	2
24063	1003	1	131	44	1	1	1	1	61	1:51:11.611	6671611	56	2	00:01:42.913	1
24064	1003	830	9	33	2	2	2	2	61	+8.961	6680572	54	5	00:01:43.345	1
24065	1003	20	6	5	3	3	3	3	61	+39.984	6711595	48	6	00:01:44.669	1
24066	1003	822	131	77	4	4	4	4	61	+51.930	6723541	42	8	00:01:44.72	1
24067	1003	8	6	7	5	5	5	5	61	+53.001	6724612	46	7	00:01:44.715	1
24068	1003	817	9	3	6	6	6	6	61	+53.982	6725593	59	3	00:01:43.12	1
24069	1003	4	1	14	11	7	7	7	61	+1:43.001	6774612	57	4	00:01:43.164	1
24070	1003	832	4	55	12	8	8	8	60	\N	\N	50	12	00:01:45.211	11
24071	1003	844	15	16	13	9	9	9	60	\N	\N	57	11	00:01:45.203	11
24072	1003	807	4	27	10	10	10	10	60	\N	\N	53	19	00:01:46.093	11
24073	1003	828	15	9	14	11	11	11	60	\N	\N	50	10	00:01:45.169	11
24074	1003	838	1	2	18	12	12	12	60	\N	\N	50	14	00:01:45.555	11
24075	1003	842	5	10	15	13	13	13	60	\N	\N	56	18	00:01:46.063	11
24076	1003	840	3	18	20	14	14	14	60	\N	\N	53	17	00:01:46.033	11
24077	1003	154	210	8	8	15	15	15	60	\N	\N	57	16	00:01:45.904	11
24078	1003	815	10	11	7	16	16	16	60	\N	\N	48	13	00:01:45.389	11
24079	1003	843	5	28	17	17	17	17	60	\N	\N	38	9	00:01:44.889	11
24080	1003	825	210	20	16	18	18	18	59	\N	\N	50	1	00:01:41.905	12
24081	1003	845	3	35	19	19	19	19	59	\N	\N	48	15	00:01:45.902	12
24082	1003	839	10	31	9	\N	R	20	0	\N	\N	\N	0	\N	4
24083	1004	1	131	44	2	1	1	1	53	1:27:25.181	5245181	50	2	00:01:35.916	1
24084	1004	822	131	77	1	2	2	2	53	+2.545	5247726	50	1	00:01:35.861	1
24085	1004	20	6	5	3	3	3	3	53	+7.487	5252668	50	3	00:01:35.99	1
24086	1004	8	6	7	4	4	4	4	53	+16.543	5261724	47	6	00:01:36.611	1
24087	1004	830	9	33	19	5	5	5	53	+31.016	5276197	45	4	00:01:36.283	1
24088	1004	817	9	3	18	6	6	6	53	+1:20.451	5325632	41	5	00:01:36.345	1
24089	1004	844	15	16	7	7	7	7	53	+1:38.390	5343571	52	9	00:01:38.107	1
24090	1004	825	210	20	5	8	8	8	52	\N	\N	52	8	00:01:38.015	11
24091	1004	839	10	31	6	9	9	9	52	\N	\N	52	12	00:01:38.366	11
24092	1004	815	10	11	8	10	10	10	52	\N	\N	47	11	00:01:38.3	11
24093	1004	154	210	8	9	11	11	11	52	\N	\N	46	10	00:01:38.244	11
24094	1004	807	4	27	12	12	12	12	52	\N	\N	52	13	00:01:39.108	11
24095	1004	828	15	9	10	13	13	13	52	\N	\N	39	7	00:01:37.931	11
24096	1004	4	1	14	16	14	14	14	52	\N	\N	44	15	00:01:39.59	11
24097	1004	840	3	18	14	15	15	15	52	\N	\N	44	14	00:01:39.435	11
24098	1004	838	1	2	15	16	16	16	51	\N	\N	41	18	00:01:39.922	12
24099	1004	832	4	55	11	17	17	17	51	\N	\N	35	16	00:01:39.731	12
24100	1004	845	3	35	13	18	18	18	51	\N	\N	43	17	00:01:39.838	12
24101	1004	842	5	10	17	\N	R	19	4	\N	\N	3	19	00:01:44.071	23
24102	1004	843	5	28	20	\N	R	20	4	\N	\N	2	20	00:01:45.852	23
24103	1005	1	131	44	1	1	1	1	53	1:27:17.062	5237062	51	2	00:01:32.785	1
24104	1005	822	131	77	2	2	2	2	53	+12.919	5249981	46	3	00:01:33.11	1
24105	1005	830	9	33	3	3	3	3	53	+14.295	5251357	50	6	00:01:33.367	1
24106	1005	817	9	3	15	4	4	4	53	+19.495	5256557	50	4	00:01:33.187	1
24107	1005	8	6	7	4	5	5	5	53	+50.998	5288060	28	12	00:01:34.223	1
24108	1005	20	6	5	8	6	6	6	53	+1:09.873	5306935	53	1	00:01:32.318	1
24109	1005	815	10	11	9	7	7	7	53	+1:19.379	5316441	43	9	00:01:34.073	1
24110	1005	154	210	8	5	8	8	8	53	+1:27.198	5324260	47	15	00:01:34.786	1
24111	1005	839	10	31	11	9	9	9	53	+1:28.055	5325117	50	14	00:01:34.67	1
24112	1005	832	4	55	13	10	10	10	52	\N	\N	50	11	00:01:34.197	11
24113	1005	842	5	10	7	11	11	11	52	\N	\N	35	10	00:01:34.133	11
24114	1005	828	15	9	20	12	12	12	52	\N	\N	8	19	00:01:36.294	11
24115	1005	843	5	28	6	13	13	13	52	\N	\N	30	16	00:01:34.857	11
24116	1005	4	1	14	18	14	14	14	52	\N	\N	28	7	00:01:33.943	11
24117	1005	838	1	2	19	15	15	15	52	\N	\N	25	18	00:01:35.023	11
24118	1005	845	3	35	17	16	16	16	52	\N	\N	41	8	00:01:33.985	11
24119	1005	840	3	18	14	17	17	17	52	\N	\N	41	5	00:01:33.354	11
24120	1005	844	15	16	10	\N	R	18	38	\N	\N	37	13	00:01:34.515	26
24121	1005	807	4	27	16	\N	R	19	37	\N	\N	32	17	00:01:34.934	5
24122	1005	825	210	20	12	\N	R	20	8	\N	\N	6	20	00:01:39.908	130
24123	1006	8	6	7	2	1	1	1	56	1:34:18.643	5658643	45	5	00:01:38.482	1
24124	1006	830	9	33	18	2	2	2	56	+1.281	5659924	45	2	00:01:38.246	1
24125	1006	1	131	44	1	3	3	3	56	+2.342	5660985	40	1	00:01:37.392	1
24126	1006	20	6	5	5	4	4	4	56	+18.222	5676865	41	3	00:01:38.28	1
24127	1006	822	131	77	3	5	5	5	56	+24.744	5683387	46	4	00:01:38.47	1
24128	1006	807	4	27	7	6	6	6	56	+1:27.210	5745853	51	8	00:01:39.548	1
24129	1006	832	4	55	11	7	7	7	56	+1:34.994	5753637	45	11	00:01:39.858	1
24130	1006	815	10	11	10	8	8	8	56	+1:41.080	5759723	45	13	00:01:39.992	1
24131	1006	843	5	28	20	9	9	9	55	\N	\N	32	6	00:01:38.963	11
24132	1006	828	15	9	16	10	10	10	55	\N	\N	36	9	00:01:39.569	11
24133	1006	838	1	2	17	11	11	11	55	\N	\N	52	12	00:01:39.915	11
24134	1006	842	5	10	19	12	12	12	55	\N	\N	33	14	00:01:40.098	11
24135	1006	845	3	35	14	13	13	13	55	\N	\N	42	7	00:01:39.24	11
24136	1006	840	3	18	15	14	14	14	54	\N	\N	38	10	00:01:39.646	12
24137	1006	844	15	16	9	\N	R	15	31	\N	\N	12	16	00:01:40.522	130
24138	1006	817	9	3	4	\N	R	16	8	\N	\N	49	15	00:01:40.433	84
24139	1006	154	210	8	8	\N	R	17	2	\N	\N	12	18	00:01:41.982	130
24140	1006	4	1	14	13	\N	R	18	1	\N	\N	5	17	00:01:40.933	4
24141	1006	839	10	31	6	\N	D	19	56	\N	\N	\N	0	\N	2
24142	1006	825	210	20	12	\N	D	20	56	\N	\N	\N	0	\N	2
24143	1007	830	9	33	2	1	1	1	71	1:38:28.851	5908851	66	2	00:01:19.186	1
24144	1007	20	6	5	4	2	2	2	71	+17.316	5926167	49	4	00:01:19.522	1
24145	1007	8	6	7	6	3	3	3	71	+49.914	5958765	19	5	00:01:20.334	1
24146	1007	1	131	44	3	4	4	4	71	+1:18.738	5987589	49	8	00:01:20.728	1
24147	1007	822	131	77	5	5	5	5	70	\N	\N	65	1	00:01:18.741	11
24148	1007	807	4	27	7	6	6	6	69	\N	\N	67	7	00:01:20.637	12
24149	1007	844	15	16	9	7	7	7	69	\N	\N	67	6	00:01:20.537	12
24150	1007	838	1	2	15	8	8	8	69	\N	\N	14	11	00:01:21.921	12
24151	1007	828	15	9	10	9	9	9	69	\N	\N	18	14	00:01:22.44	12
24152	1007	842	5	10	20	10	10	10	69	\N	\N	69	17	00:01:22.755	12
24153	1007	839	10	31	11	11	11	11	69	\N	\N	6	15	00:01:22.629	12
24154	1007	840	3	18	17	12	12	12	69	\N	\N	27	18	00:01:22.983	12
24155	1007	845	3	35	19	13	13	13	69	\N	\N	66	16	00:01:22.64	12
24156	1007	843	5	28	14	14	14	14	69	\N	\N	26	13	00:01:22.438	12
24157	1007	825	210	20	16	15	15	15	69	\N	\N	45	10	00:01:21.874	12
24158	1007	154	210	8	18	16	16	16	68	\N	\N	46	9	00:01:21.37	13
24159	1007	817	9	3	1	\N	R	17	61	\N	\N	57	3	00:01:19.462	5
24160	1007	815	10	11	13	\N	R	18	38	\N	\N	6	19	00:01:23.545	23
24161	1007	832	4	55	8	\N	R	19	28	\N	\N	6	12	00:01:22.386	22
24162	1007	4	1	14	12	\N	R	20	3	\N	\N	3	20	00:01:24.197	5
24163	1008	1	131	44	1	1	1	1	71	1:27:09.066	5229066	70	7	00:01:11.795	1
24164	1008	830	9	33	5	2	2	2	71	+1.469s	5230535	61	4	00:01:11.578	1
24165	1008	8	6	7	4	3	3	3	71	+4.764s	5233830	64	6	00:01:11.769	1
24166	1008	817	9	3	11	4	4	4	71	+5.193s	5234259	62	3	00:01:11.343	1
24167	1008	822	131	77	3	5	5	5	71	+22.943s	5252009	65	1	00:01:10.54	1
24168	1008	20	6	5	2	6	6	6	71	+26.997s	5256063	71	2	00:01:10.831	1
24169	1008	844	15	16	7	7	7	7	71	+44.199s	5273265	70	8	00:01:12.082	1
24170	1008	154	210	8	8	8	8	8	71	+51.230s	5280296	71	12	00:01:12.362	1
24171	1008	825	210	20	10	9	9	9	71	+52.857s	5281923	67	10	00:01:12.206	1
24172	1008	815	10	11	12	10	10	10	70	\N	\N	58	13	00:01:12.472	11
24173	1008	843	5	28	16	11	11	11	70	\N	\N	53	15	00:01:12.949	11
24174	1008	832	4	55	15	12	12	12	70	\N	\N	50	9	00:01:12.169	11
24175	1008	842	5	10	9	13	13	13	70	\N	\N	55	17	00:01:13.822	11
24176	1008	838	1	2	20	14	14	14	70	\N	\N	68	16	00:01:12.968	11
24177	1008	839	10	31	18	15	15	15	70	\N	\N	70	11	00:01:12.352	11
24178	1008	845	3	35	14	16	16	16	69	\N	\N	52	19	00:01:14.262	12
24179	1008	4	1	14	17	17	17	17	69	\N	\N	57	14	00:01:12.643	12
24180	1008	840	3	18	19	18	18	18	69	\N	\N	68	5	00:01:11.751	12
24181	1008	807	4	27	13	\N	R	19	32	\N	\N	30	18	00:01:14.029	25
24182	1008	828	15	9	6	\N	R	20	20	\N	\N	3	20	00:01:15.281	4
24183	1009	1	131	44	1	1	1	1	55	1:39:40.382	5980382	53	5	00:01:41.357	1
24184	1009	20	6	5	3	2	2	2	55	+2.581	5982963	54	1	00:01:40.867	1
24185	1009	830	9	33	6	3	3	3	55	+12.706	5993088	51	6	00:01:41.909	1
24186	1009	817	9	3	5	4	4	4	55	+15.379	5995761	35	3	00:01:41.249	1
24187	1009	822	131	77	2	5	5	5	55	+47.957	6028339	42	2	00:01:40.953	1
24188	1009	832	4	55	11	6	6	6	55	+1:12.548	6052930	54	4	00:01:41.351	1
24189	1009	844	15	16	8	7	7	7	55	+1:30.789	6071171	54	10	00:01:42.876	1
24190	1009	815	10	11	14	8	8	8	55	+1:31.275	6071657	53	8	00:01:42.816	1
24191	1009	154	210	8	7	9	9	9	54	\N	\N	54	11	00:01:43.195	11
24192	1009	825	210	20	13	10	10	10	54	\N	\N	53	9	00:01:42.822	11
24193	1009	4	1	14	15	11	11	11	54	\N	\N	53	7	00:01:42.393	11
24194	1009	843	5	28	16	12	12	12	54	\N	\N	53	17	00:01:44.174	11
24195	1009	840	3	18	20	13	13	13	54	\N	\N	53	16	00:01:44.033	11
24196	1009	838	1	2	18	14	14	14	54	\N	\N	53	12	00:01:43.249	11
24197	1009	845	3	35	19	15	15	15	54	\N	\N	54	14	00:01:43.831	11
24198	1009	842	5	10	17	\N	R	16	46	\N	\N	42	15	00:01:43.988	5
24199	1009	839	10	31	9	\N	R	17	44	\N	\N	41	13	00:01:43.591	5
24200	1009	828	15	9	12	\N	R	18	24	\N	\N	22	19	00:01:46.077	75
24201	1009	8	6	7	4	\N	R	19	6	\N	\N	5	18	00:01:45.198	75
24202	1009	807	4	27	10	\N	R	20	0	\N	\N	\N	0	\N	4
24203	1010	822	131	77	2	1	1	1	58	1:25:27.325	5127325	57	1	00:01:25.58	1
24204	1010	1	131	44	1	2	2	2	58	+20.886	5148211	57	2	00:01:26.057	1
24205	1010	830	9	33	4	3	3	3	58	+22.520	5149845	57	3	00:01:26.256	1
24206	1010	20	6	5	3	4	4	4	58	+57.109	5184434	16	8	00:01:27.954	1
24207	1010	844	6	16	5	5	5	5	58	+58.203	5185528	58	4	00:01:26.926	1
24208	1010	825	210	20	7	6	6	6	58	+1:27.156	5214481	56	9	00:01:28.182	1
24209	1010	807	4	27	11	7	7	7	57	\N	\N	52	12	00:01:28.444	11
24210	1010	8	51	7	9	8	8	8	57	\N	\N	52	11	00:01:28.27	11
24211	1010	840	211	18	16	9	9	9	57	\N	\N	29	7	00:01:27.568	11
24212	1010	826	5	26	15	10	10	10	57	\N	\N	39	6	00:01:27.448	11
24213	1010	842	9	10	17	11	11	11	57	\N	\N	39	5	00:01:27.229	11
24214	1010	846	1	4	8	12	12	12	57	\N	\N	17	16	00:01:28.555	11
24215	1010	815	211	11	10	13	13	13	57	\N	\N	41	15	00:01:28.485	11
24216	1010	848	5	23	13	14	14	14	57	\N	\N	43	10	00:01:28.188	11
24217	1010	841	51	99	14	15	15	15	57	\N	\N	29	14	00:01:28.479	11
24218	1010	847	3	63	19	16	16	16	56	\N	\N	55	17	00:01:28.713	12
24219	1010	9	3	88	20	17	17	17	55	\N	\N	30	18	00:01:29.284	13
24220	1010	154	210	8	6	\N	R	18	29	\N	\N	17	13	00:01:28.462	36
24221	1010	817	4	3	12	\N	R	19	28	\N	\N	18	19	00:01:29.848	137
24222	1010	832	1	55	18	\N	R	20	9	\N	\N	9	20	00:01:30.899	5
24223	1011	1	131	44	3	1	1	1	57	1:34:21.295	5661295	36	2	00:01:33.528	1
24224	1011	822	131	77	4	2	2	2	57	+2.980	5664275	42	3	00:01:34.209	1
24225	1011	844	6	16	1	3	3	3	57	+6.131	5667426	38	1	00:01:33.411	1
24226	1011	830	9	33	5	4	4	4	57	+6.408	5667703	47	9	00:01:35.311	1
24227	1011	20	6	5	2	5	5	5	57	+36.068	5697363	43	4	00:01:34.895	1
24228	1011	846	1	4	9	6	6	6	57	+45.754	5707049	14	12	00:01:35.777	1
24229	1011	8	51	7	8	7	7	7	57	+47.470	5708765	45	11	00:01:35.589	1
24230	1011	842	9	10	13	8	8	8	57	+58.094	5719389	42	8	00:01:35.291	1
24231	1011	848	5	23	12	9	9	9	57	+1:02.697	5723992	39	16	00:01:36.752	1
24232	1011	815	211	11	14	10	10	10	57	+1:03.696	5724991	51	14	00:01:36.33	1
24233	1011	841	51	99	16	11	11	11	57	+1:04.599	5725894	42	7	00:01:35.237	1
24234	1011	826	5	26	15	12	12	12	56	\N	\N	40	5	00:01:34.934	11
24235	1011	825	210	20	6	13	13	13	56	\N	\N	41	13	00:01:35.892	11
24236	1011	840	211	18	18	14	14	14	56	\N	\N	31	17	00:01:37.037	11
24237	1011	847	3	63	19	15	15	15	56	\N	\N	14	19	00:01:37.313	11
24238	1011	9	3	88	20	16	16	16	55	\N	\N	13	20	00:01:37.903	12
24239	1011	807	4	27	17	\N	R	17	53	\N	\N	14	6	00:01:35.215	5
24240	1011	817	4	3	10	\N	R	18	53	\N	\N	42	15	00:01:36.697	60
24241	1011	832	1	55	7	\N	R	19	53	\N	\N	42	10	00:01:35.586	130
24242	1011	154	210	8	11	\N	R	20	16	\N	\N	3	18	00:01:37.262	31
24243	1012	1	131	44	2	1	1	1	56	1:32:06.350	5526350	47	5	00:01:35.892	1
24244	1012	822	131	77	1	2	2	2	56	+6.552	5532902	38	4	00:01:34.872	1
24245	1012	20	6	5	3	3	3	3	56	+13.774	5540124	37	2	00:01:34.836	1
24246	1012	830	9	33	5	4	4	4	56	+27.627	5553977	45	6	00:01:36.143	1
24247	1012	844	6	16	4	5	5	5	56	+31.276	5557626	45	3	00:01:34.86	1
24248	1012	842	9	10	6	6	6	6	56	+1:29.307	5615657	55	1	00:01:34.742	1
24249	1012	817	4	3	7	7	7	7	55	\N	\N	38	16	00:01:38.632	11
24250	1012	815	211	11	12	8	8	8	55	\N	\N	37	17	00:01:38.702	11
24251	1012	8	51	7	13	9	9	9	55	\N	\N	27	12	00:01:37.812	11
24252	1012	848	5	23	0	10	10	10	55	\N	\N	22	18	00:01:38.901	11
24253	1012	154	210	8	10	11	11	11	55	\N	\N	37	8	00:01:36.873	11
24254	1012	840	211	18	16	12	12	12	55	\N	\N	46	7	00:01:36.678	11
24255	1012	825	210	20	9	13	13	13	55	\N	\N	35	10	00:01:37.471	11
24256	1012	832	1	55	14	14	14	14	55	\N	\N	44	11	00:01:37.502	11
24257	1012	841	51	99	19	15	15	15	55	\N	\N	32	14	00:01:38.048	11
24258	1012	847	3	63	17	16	16	16	54	\N	\N	51	9	00:01:37.283	12
24259	1012	9	3	88	18	17	17	17	54	\N	\N	28	20	00:01:39.772	12
24260	1012	846	1	4	15	18	18	18	50	\N	\N	37	15	00:01:38.346	4
24261	1012	826	5	26	11	\N	R	19	41	\N	\N	27	13	00:01:37.975	4
24262	1012	807	4	27	8	\N	R	20	16	\N	\N	14	19	00:01:39.677	131
24263	1013	822	131	77	1	1	1	1	51	1:31:52.942	5512942	50	2	00:01:44.024	1
24264	1013	1	131	44	2	2	2	2	51	+1.524	5514466	48	3	00:01:44.166	1
24265	1013	20	6	5	3	3	3	3	51	+11.739	5524681	46	4	00:01:44.629	1
24266	1013	830	9	33	4	4	4	4	51	+17.493	5530435	39	5	00:01:44.794	1
24267	1013	844	6	16	8	5	5	5	51	+1:09.107	5582049	50	1	00:01:43.009	1
24268	1013	815	211	11	5	6	6	6	51	+1:16.416	5589358	49	7	00:01:45.524	1
24269	1013	832	1	55	9	7	7	7	51	+1:23.826	5596768	43	10	00:01:45.807	1
24270	1013	846	1	4	7	8	8	8	51	+1:40.268	5613210	43	6	00:01:45.394	1
24271	1013	840	211	18	13	9	9	9	51	+1:43.816	5616758	38	12	00:01:46.009	1
24272	1013	8	51	7	0	10	10	10	50	\N	\N	48	13	00:01:46.479	11
24273	1013	848	5	23	11	11	11	11	50	\N	\N	49	9	00:01:45.754	11
24274	1013	841	51	99	17	12	12	12	50	\N	\N	45	11	00:01:45.969	11
24275	1013	825	210	20	12	13	13	13	50	\N	\N	42	14	00:01:46.682	11
24276	1013	807	4	27	15	14	14	14	50	\N	\N	43	17	00:01:47.407	11
24277	1013	847	3	63	16	15	15	15	49	\N	\N	42	16	00:01:47.251	12
24278	1013	9	3	88	0	16	16	16	49	\N	\N	45	19	00:01:47.709	12
24279	1013	842	9	10	0	\N	R	17	38	\N	\N	34	8	00:01:45.712	7
24280	1013	154	210	8	14	\N	R	18	38	\N	\N	33	20	00:01:48.517	23
24281	1013	826	5	26	6	\N	R	19	33	\N	\N	28	18	00:01:47.681	4
24282	1013	817	4	3	10	\N	R	20	31	\N	\N	29	15	00:01:46.767	4
24283	1014	1	131	44	2	1	1	1	66	1:35:50.443	5750443	54	1	00:01:18.492	1
24284	1014	822	131	77	1	2	2	2	66	+4.074	5754517	55	2	00:01:18.737	1
24285	1014	830	9	33	4	3	3	3	66	+7.679	5758122	57	3	00:01:19.769	1
24286	1014	20	6	5	3	4	4	4	66	+9.167	5759610	64	4	00:01:19.82	1
24287	1014	844	6	16	5	5	5	5	66	+13.361	5763804	57	5	00:01:20.002	1
24288	1014	842	9	10	6	6	6	6	66	+19.576	5770019	57	6	00:01:20.536	1
24289	1014	825	210	20	8	7	7	7	66	+28.159	5778602	66	9	00:01:20.77	1
24290	1014	832	1	55	12	8	8	8	66	+32.342	5782785	59	10	00:01:20.859	1
24291	1014	826	5	26	9	9	9	9	66	+33.056	5783499	64	8	00:01:20.726	1
24292	1014	154	210	8	7	10	10	10	66	+34.641	5785084	64	12	00:01:21.057	1
24293	1014	848	5	23	11	11	11	11	66	+35.445	5785888	65	11	00:01:21.028	1
24294	1014	817	4	3	13	12	12	12	66	+36.758	5787201	56	7	00:01:20.615	1
24295	1014	807	4	27	0	13	13	13	66	+39.241	5789684	65	13	00:01:21.282	1
24296	1014	8	51	7	14	14	14	14	66	+41.803	5792246	66	14	00:01:21.382	1
24297	1014	815	211	11	15	15	15	15	66	+46.877	5797320	65	16	00:01:21.859	1
24298	1014	841	51	99	18	16	16	16	66	+47.691	5798134	64	15	00:01:21.833	1
24299	1014	847	3	63	19	17	17	17	65	\N	\N	64	17	00:01:22.382	11
24300	1014	9	3	88	17	18	18	18	65	\N	\N	65	19	00:01:23.202	11
24301	1014	840	211	18	16	\N	R	19	44	\N	\N	28	20	00:01:23.226	4
24302	1014	846	1	4	10	\N	R	20	44	\N	\N	28	18	00:01:22.561	4
24306	1015	1	131	44	1	1	1	1	78	1:43:28.437	6208437	9	6	00:01:16.167	1
24307	1015	20	6	5	4	2	2	2	78	+2.602	6211039	9	9	00:01:16.277	1
24308	1015	822	131	77	2	3	3	3	78	+3.162	6211599	65	2	00:01:15.163	1
24309	1015	830	9	33	3	4	4	4	78	+5.537	6213974	9	7	00:01:16.229	1
24310	1015	842	9	10	8	5	5	5	78	+9.946	6218383	72	1	00:01:14.279	1
24311	1015	832	1	55	9	6	6	6	78	+53.454	6261891	32	5	00:01:15.891	1
24312	1015	826	5	26	7	7	7	7	78	+54.574	6263011	31	10	00:01:16.288	1
24313	1015	848	5	23	10	8	8	8	78	+55.200	6263637	43	3	00:01:15.607	1
24314	1015	817	4	3	6	9	9	9	78	+1:00.894	6269331	78	4	00:01:15.697	1
24315	1015	154	210	8	13	10	10	10	78	+1:01.034	6269471	41	16	00:01:16.746	1
24316	1015	846	1	4	12	11	11	11	78	+1:06.801	6275238	61	13	00:01:16.413	1
24317	1015	825	210	20	5	12	12	12	77	\N	\N	61	17	00:01:16.992	11
24318	1015	815	211	11	16	13	13	13	77	\N	\N	67	15	00:01:16.613	11
24319	1015	807	4	27	11	14	14	14	77	\N	\N	65	8	00:01:16.276	11
24320	1015	847	3	63	19	15	15	15	77	\N	\N	76	18	00:01:17.038	11
24321	1015	840	211	18	17	16	16	16	77	\N	\N	45	12	00:01:16.379	11
24322	1015	8	51	7	14	17	17	17	77	\N	\N	50	14	00:01:16.436	11
24323	1015	9	3	88	20	18	18	18	77	\N	\N	32	19	00:01:17.388	11
24324	1015	841	51	99	18	19	19	19	76	\N	\N	46	11	00:01:16.299	12
24325	1015	844	6	16	15	\N	R	20	16	\N	\N	6	20	00:01:19.151	4
24326	1016	1	131	44	2	1	1	1	70	1:29:07.084	5347084	62	4	00:01:14.813	1
24327	1016	20	6	5	1	2	2	2	70	+3.658	5350742	57	5	00:01:14.875	1
24328	1016	844	6	16	3	3	3	3	70	+4.696	5351780	63	2	00:01:14.356	1
24329	1016	822	131	77	6	4	4	4	70	+51.043	5398127	69	1	00:01:13.078	1
24330	1016	830	9	33	9	5	5	5	70	+57.655	5404739	67	3	00:01:14.767	1
24331	1016	817	4	3	4	6	6	6	69	\N	\N	55	9	00:01:16.075	11
24332	1016	807	4	27	7	7	7	7	69	\N	\N	57	7	00:01:15.995	11
24333	1016	842	9	10	5	8	8	8	69	\N	\N	51	10	00:01:16.157	11
24334	1016	840	211	18	17	9	9	9	69	\N	\N	47	8	00:01:16.043	11
24335	1016	826	5	26	10	10	10	10	69	\N	\N	44	11	00:01:16.198	11
24336	1016	832	1	55	11	11	11	11	69	\N	\N	37	15	00:01:16.471	11
24337	1016	815	211	11	15	12	12	12	69	\N	\N	61	13	00:01:16.314	11
24338	1016	841	51	99	12	13	13	13	69	\N	\N	69	14	00:01:16.365	11
24339	1016	154	210	8	14	14	14	14	69	\N	\N	60	12	00:01:16.245	11
24340	1016	8	51	7	16	15	15	15	69	\N	\N	60	6	00:01:15.442	11
24341	1016	847	3	63	18	16	16	16	68	\N	\N	58	17	00:01:17.241	12
24342	1016	825	210	20	0	17	17	17	68	\N	\N	41	19	00:01:17.309	12
24343	1016	9	3	88	19	18	18	18	67	\N	\N	64	18	00:01:17.285	13
24344	1016	848	5	23	13	\N	R	19	59	\N	\N	47	16	00:01:17.151	130
24345	1016	846	1	4	8	\N	R	20	8	\N	\N	4	20	00:01:18.023	22
24346	1017	1	131	44	1	1	1	1	53	1:24:31.198	5071198	53	2	00:01:32.764	1
24347	1017	822	131	77	2	2	2	2	53	+18.056	5089254	43	3	00:01:33.586	1
24348	1017	844	6	16	3	3	3	3	53	+18.985	5090183	40	4	00:01:33.828	1
24349	1017	830	9	33	4	4	4	4	53	+34.905	5106103	38	5	00:01:34.162	1
24350	1017	20	6	5	7	5	5	5	53	+1:02.796	5133994	53	1	00:01:32.74	1
24351	1017	832	1	55	6	6	6	6	53	+1:35.462	5166660	52	6	00:01:34.561	1
24352	1017	8	51	7	12	7	7	7	52	\N	\N	47	8	00:01:34.873	11
24353	1017	807	4	27	13	8	8	8	52	\N	\N	46	10	00:01:34.95	11
24354	1017	846	1	4	5	9	9	9	52	\N	\N	45	7	00:01:34.754	11
24355	1017	842	9	10	9	10	10	10	52	\N	\N	47	15	00:01:35.197	11
24356	1017	817	4	3	8	11	11	11	52	\N	\N	42	14	00:01:35.15	11
24357	1017	815	211	11	14	12	12	12	52	\N	\N	42	11	00:01:35.014	11
24358	1017	840	211	18	17	13	13	13	52	\N	\N	44	9	00:01:34.924	11
24359	1017	826	5	26	19	14	14	14	52	\N	\N	43	16	00:01:35.225	11
24360	1017	848	5	23	11	15	15	15	52	\N	\N	51	12	00:01:35.029	11
24361	1017	841	51	99	10	16	16	16	52	\N	\N	50	13	00:01:35.115	11
24362	1017	825	210	20	15	17	17	17	52	\N	\N	50	18	00:01:35.692	11
24363	1017	9	3	88	18	18	18	18	51	\N	\N	50	20	00:01:36.608	12
24364	1017	847	3	63	20	19	19	19	51	\N	\N	51	19	00:01:35.83	12
24365	1017	154	210	8	16	20	20	20	44	\N	\N	42	17	00:01:35.691	31
24366	1018	830	9	33	2	1	1	1	71	1:22:01.822	4921822	60	1	00:01:07.475	1
24367	1018	844	6	16	1	2	2	2	71	+2.724	4924546	58	3	00:01:07.994	1
24368	1018	822	131	77	3	3	3	3	71	+18.960	4940782	53	7	00:01:08.565	1
24369	1018	20	6	5	9	4	4	4	71	+19.610	4941432	62	2	00:01:07.676	1
24370	1018	1	131	44	4	5	5	5	71	+22.805	4944627	69	5	00:01:08.05	1
24371	1018	846	1	4	5	6	6	6	70	\N	\N	69	8	00:01:08.699	11
24372	1018	842	9	10	8	7	7	7	70	\N	\N	63	9	00:01:08.79	11
24373	1018	832	1	55	19	8	8	8	70	\N	\N	53	6	00:01:08.117	11
24374	1018	8	51	7	6	9	9	9	70	\N	\N	57	15	00:01:09.126	11
24375	1018	841	51	99	7	10	10	10	70	\N	\N	57	13	00:01:09.051	11
24376	1018	815	211	11	13	11	11	11	70	\N	\N	67	14	00:01:09.061	11
24377	1018	817	4	3	12	12	12	12	70	\N	\N	65	4	00:01:08.019	11
24378	1018	807	4	27	15	13	13	13	70	\N	\N	59	16	00:01:09.248	11
24379	1018	840	211	18	14	14	14	14	70	\N	\N	57	17	00:01:09.288	11
24380	1018	848	5	23	18	15	15	15	70	\N	\N	59	11	00:01:08.946	11
24381	1018	154	210	8	11	16	16	16	70	\N	\N	56	12	00:01:08.987	11
24382	1018	826	5	26	16	17	17	17	70	\N	\N	58	18	00:01:09.498	11
24383	1018	847	3	63	0	18	18	18	69	\N	\N	52	19	00:01:09.926	12
24384	1018	825	210	20	10	19	19	19	69	\N	\N	69	10	00:01:08.903	12
24385	1018	9	3	88	17	20	20	20	68	\N	\N	55	20	00:01:10.964	13
24386	1019	1	131	44	2	1	1	1	52	1:21:08.452	4868452	52	1	00:01:27.369	1
24387	1019	822	131	77	1	2	2	2	52	+24.928	4893380	47	2	00:01:27.406	1
24388	1019	844	6	16	3	3	3	3	52	+30.117	4898569	47	5	00:01:29.313	1
24389	1019	842	9	10	5	4	4	4	52	+34.692	4903144	48	8	00:01:29.544	1
24390	1019	830	9	33	4	5	5	5	52	+39.458	4907910	45	4	00:01:29.272	1
24391	1019	832	1	55	13	6	6	6	52	+53.639	4922091	50	11	00:01:29.757	1
24392	1019	817	4	3	7	7	7	7	52	+54.401	4922853	50	9	00:01:29.624	1
24393	1019	8	51	7	12	8	8	8	52	+1:05.540	4933992	51	14	00:01:30.034	1
24394	1019	826	5	26	17	9	9	9	52	+1:06.720	4935172	51	12	00:01:29.91	1
24395	1019	807	4	27	10	10	10	10	52	+1:12.733	4941185	51	13	00:01:29.949	1
24396	1019	846	1	4	8	11	11	11	52	+1:14.281	4942733	50	10	00:01:29.636	1
24397	1019	848	5	23	9	12	12	12	52	+1:15.617	4944069	46	15	00:01:30.872	1
24398	1019	840	211	18	18	13	13	13	52	+1:21.086	4949538	49	6	00:01:29.39	1
24399	1019	847	3	63	19	14	14	14	51	\N	\N	50	16	00:01:31.013	11
24400	1019	9	3	88	20	15	15	15	51	\N	\N	50	17	00:01:31.509	11
24401	1019	20	6	5	6	16	16	16	51	\N	\N	46	3	00:01:28.733	11
24402	1019	815	211	11	15	17	17	17	51	\N	\N	50	7	00:01:29.456	11
24403	1019	841	51	99	11	\N	R	18	18	\N	\N	17	18	00:01:32.464	20
24404	1019	154	210	8	14	\N	R	19	9	\N	\N	4	20	00:01:34.35	4
24405	1019	825	210	20	16	\N	R	20	6	\N	\N	5	19	00:01:33.425	4
24406	1020	830	9	33	2	1	1	1	64	1:44:31.275	6271275	61	1	00:01:16.645	1
24407	1020	20	6	5	20	2	2	2	64	+7.333	6278608	63	2	00:01:16.794	1
24408	1020	826	5	26	14	3	3	3	64	+8.305	6279580	61	6	00:01:17.708	1
24409	1020	840	211	18	15	4	4	4	64	+8.966	6280241	61	8	00:01:17.831	1
24410	1020	832	1	55	7	5	5	5	64	+9.583	6280858	63	9	00:01:17.841	1
24411	1020	848	5	23	16	6	6	6	64	+10.052	6281327	63	10	00:01:17.85	1
24412	1020	154	210	8	6	7	7	7	64	+16.838	6288113	55	7	00:01:17.746	1
24413	1020	825	210	20	12	8	8	8	64	+18.765	6290040	62	5	00:01:17.507	1
24414	1020	1	131	44	1	9	9	9	64	+19.667	6290942	64	12	00:01:18.811	1
24415	1020	9	3	88	18	10	10	10	64	+24.987	6296262	63	13	00:01:19.062	1
24416	1020	847	3	63	17	11	11	11	64	+26.404	6297679	60	3	00:01:17.485	1
24417	1020	8	51	7	5	12	12	12	64	+42.214	6313489	60	15	00:01:19.563	1
24418	1020	841	51	99	11	13	13	13	64	+43.849	6315124	60	14	00:01:19.3	1
24419	1020	842	9	10	4	14	14	14	61	\N	\N	56	4	00:01:17.495	4
24420	1020	822	131	77	3	\N	R	15	56	\N	\N	54	11	00:01:18.272	3
24421	1020	807	4	27	9	\N	R	16	39	\N	\N	18	17	00:01:29.576	3
24422	1020	844	6	16	10	\N	R	17	27	\N	\N	17	16	00:01:27.697	3
24423	1020	846	1	4	19	\N	R	18	25	\N	\N	16	18	00:01:31.081	75
24424	1020	817	4	3	13	\N	R	19	13	\N	\N	10	19	00:01:32.654	43
24425	1020	815	211	11	8	\N	R	20	1	\N	\N	\N	0	\N	20
24426	1021	1	131	44	3	1	1	1	70	1:35:03.796	5703796	60	2	00:01:18.528	1
24427	1021	830	9	33	1	2	2	2	70	+17.796	5721592	69	1	00:01:17.103	1
24428	1021	20	6	5	5	3	3	3	70	+1:01.433	5765229	65	4	00:01:19.786	1
24429	1021	844	6	16	4	4	4	4	70	+1:05.250	5769046	49	5	00:01:20.493	1
24430	1021	832	1	55	8	5	5	5	69	\N	\N	66	10	00:01:21.002	11
24431	1021	842	9	10	6	6	6	6	69	\N	\N	65	12	00:01:21.045	11
24432	1021	8	51	7	10	7	7	7	69	\N	\N	65	9	00:01:20.88	11
24433	1021	822	131	77	2	8	8	8	69	\N	\N	59	3	00:01:19.331	11
24434	1021	846	1	4	7	9	9	9	69	\N	\N	65	13	00:01:21.188	11
24435	1021	848	5	23	12	10	10	10	69	\N	\N	65	7	00:01:20.621	11
24436	1021	815	211	11	16	11	11	11	69	\N	\N	47	15	00:01:21.734	11
24437	1021	807	4	27	11	12	12	12	69	\N	\N	59	14	00:01:21.65	11
24438	1021	825	210	20	14	13	13	13	69	\N	\N	67	11	00:01:21.008	11
24439	1021	817	4	3	20	14	14	14	69	\N	\N	49	8	00:01:20.839	11
24440	1021	826	5	26	13	15	15	15	68	\N	\N	55	16	00:01:21.932	12
24441	1021	847	3	63	15	16	16	16	68	\N	\N	66	17	00:01:22.386	12
24442	1021	840	211	18	18	17	17	17	68	\N	\N	52	6	00:01:20.603	12
24443	1021	841	51	99	17	18	18	18	68	\N	\N	64	19	00:01:23.134	12
24444	1021	9	3	88	19	19	19	19	67	\N	\N	42	20	00:01:23.436	13
24445	1021	154	210	8	9	\N	R	20	49	\N	\N	46	18	00:01:22.809	34
24446	1022	844	6	16	1	1	1	1	44	1:23:45.710	5025710	23	4	00:01:46.664	1
24447	1022	1	131	44	3	2	2	2	44	+0.981	5026691	24	3	00:01:46.58	1
24448	1022	822	131	77	4	3	3	3	44	+12.585	5038295	27	2	00:01:46.465	1
24449	1022	20	6	5	2	4	4	4	44	+26.422	5052132	36	1	00:01:46.409	1
24450	1022	848	9	23	17	5	5	5	44	+1:21.325	5107035	41	5	00:01:47.507	1
24451	1022	815	211	11	7	6	6	6	44	+1:24.448	5110158	29	13	00:01:48.781	1
24452	1022	826	5	26	19	7	7	7	44	+1:29.657	5115367	26	7	00:01:48.143	1
24453	1022	807	4	27	12	8	8	8	44	+1:46.639	5132349	34	9	00:01:48.349	1
24454	1022	842	5	10	13	9	9	9	44	+1:49.168	5134878	21	17	00:01:49.7	1
24455	1022	840	211	18	16	10	10	10	44	+1:49.838	5135548	34	10	00:01:48.357	1
24456	1022	846	1	4	11	11	11	11	43	\N	\N	21	8	00:01:48.321	5
24457	1022	825	210	20	8	12	12	12	43	\N	\N	33	11	00:01:48.677	11
24458	1022	154	210	8	9	13	13	13	43	\N	\N	18	16	00:01:49.274	11
24459	1022	817	4	3	10	14	14	14	43	\N	\N	21	18	00:01:50.451	11
24460	1022	847	3	63	14	15	15	15	43	\N	\N	34	14	00:01:48.86	11
24461	1022	8	51	7	6	16	16	16	43	\N	\N	37	12	00:01:48.753	11
24462	1022	9	3	88	0	17	17	17	43	\N	\N	33	15	00:01:49.22	11
24463	1022	841	51	99	18	18	18	18	42	\N	\N	31	6	00:01:47.56	3
24464	1022	832	1	55	15	\N	R	19	1	\N	\N	\N	0	\N	75
24465	1022	830	9	33	5	\N	R	20	0	\N	\N	\N	0	\N	3
24466	1023	844	6	16	1	1	1	1	53	1:15:26.665	4526665	47	4	00:01:23.009	1
24467	1023	822	131	77	3	2	2	2	53	+0.835	4527500	47	3	00:01:22.859	1
24468	1023	1	131	44	2	3	3	3	53	+35.199	4561864	51	1	00:01:21.779	1
24469	1023	817	4	3	5	4	4	4	53	+45.515	4572180	53	7	00:01:23.466	1
24470	1023	807	4	27	6	5	5	5	53	+58.165	4584830	53	8	00:01:23.641	1
24471	1023	848	9	23	8	6	6	6	53	+59.315	4585980	45	6	00:01:23.364	1
24472	1023	815	211	11	18	7	7	7	53	+1:13.802	4600467	35	9	00:01:23.77	1
24473	1023	830	9	33	19	8	8	8	53	+1:14.492	4601157	41	5	00:01:23.143	1
24474	1023	841	51	99	10	9	9	9	52	\N	\N	44	15	00:01:24.503	11
24475	1023	846	1	4	16	10	10	10	52	\N	\N	52	11	00:01:24.044	11
24476	1023	842	5	10	17	11	11	11	52	\N	\N	51	10	00:01:23.885	11
24477	1023	840	211	18	9	12	12	12	52	\N	\N	31	12	00:01:24.165	11
24478	1023	20	6	5	4	13	13	13	52	\N	\N	50	2	00:01:22.799	11
24479	1023	847	3	63	14	14	14	14	52	\N	\N	51	16	00:01:24.842	11
24480	1023	8	51	7	0	15	15	15	52	\N	\N	52	13	00:01:24.419	11
24481	1023	154	210	8	13	16	16	16	52	\N	\N	31	17	00:01:24.985	11
24482	1023	9	3	88	15	17	17	17	51	\N	\N	47	18	00:01:24.989	12
24483	1023	825	210	20	11	\N	R	18	43	\N	\N	38	14	00:01:24.443	9
24484	1023	826	5	26	12	\N	R	19	29	\N	\N	19	20	00:01:25.772	5
24485	1023	832	1	55	7	\N	R	20	27	\N	\N	10	19	00:01:25.637	36
24486	1024	20	6	5	3	1	1	1	61	1:58:33.667	7113667	57	5	00:01:44.802	1
24487	1024	844	6	16	1	2	2	2	61	+2.641	7116308	59	4	00:01:44.723	1
24488	1024	830	9	33	4	3	3	3	61	+3.821	7117488	56	8	00:01:45.176	1
24489	1024	1	131	44	2	4	4	4	61	+4.608	7118275	58	7	00:01:44.914	1
24490	1024	822	131	77	5	5	5	5	61	+6.119	7119786	58	2	00:01:43.534	1
24491	1024	848	9	23	6	6	6	6	61	+11.663	7125330	59	9	00:01:45.26	1
24492	1024	846	1	4	9	7	7	7	61	+14.769	7128436	58	11	00:01:45.716	1
24493	1024	842	5	10	11	8	8	8	61	+15.547	7129214	58	13	00:01:45.769	1
24494	1024	807	4	27	8	9	9	9	61	+16.718	7130385	59	12	00:01:45.765	1
24495	1024	841	51	99	10	10	10	10	61	+27.855	7141522	59	10	00:01:45.63	1
24496	1024	154	210	8	17	11	11	11	61	+35.436	7149103	54	16	00:01:46.274	1
24497	1024	832	1	55	7	12	12	12	61	+35.974	7149641	41	15	00:01:45.969	1
24498	1024	840	211	18	16	13	13	13	61	+36.419	7150086	57	6	00:01:44.896	1
24499	1024	817	4	3	20	14	14	14	61	+37.660	7151327	55	14	00:01:45.915	1
24500	1024	826	5	26	14	15	15	15	61	+38.178	7151845	57	3	00:01:44.371	1
24501	1024	9	3	88	19	16	16	16	61	+47.024	7160691	59	18	00:01:46.793	1
24502	1024	825	210	20	13	17	17	17	61	+1:26.522	7200189	58	1	00:01:42.301	1
24503	1024	8	51	7	12	\N	R	18	49	\N	\N	18	19	00:01:47.062	4
24504	1024	815	211	11	15	\N	R	19	42	\N	\N	15	17	00:01:46.683	5
24505	1024	847	3	63	18	\N	R	20	34	\N	\N	29	20	00:01:48.285	4
24506	1025	1	131	44	2	1	1	1	53	1:33:38.992	5618992	51	1	00:01:35.761	1
24507	1025	822	131	77	4	2	2	2	53	+3.829	5622821	50	3	00:01:36.316	1
24508	1025	844	6	16	1	3	3	3	53	+5.212	5624204	52	2	00:01:36.193	1
24509	1025	830	9	33	9	4	4	4	53	+14.210	5633202	47	5	00:01:36.937	1
24510	1025	848	9	23	0	5	5	5	53	+38.348	5657340	50	4	00:01:36.762	1
24511	1025	832	1	55	5	6	6	6	53	+45.889	5664881	53	6	00:01:38.02	1
24512	1025	815	211	11	11	7	7	7	53	+48.728	5667720	49	7	00:01:38.043	1
24513	1025	846	1	4	7	8	8	8	53	+57.749	5676741	52	11	00:01:38.301	1
24514	1025	825	210	20	13	9	9	9	53	+58.779	5677771	53	8	00:01:38.13	1
24515	1025	807	4	27	6	10	10	10	53	+59.841	5678833	53	12	00:01:38.519	1
24516	1025	840	211	18	14	11	11	11	53	+1:00.821	5679813	53	15	00:01:38.611	1
24517	1025	826	5	26	19	12	12	12	53	+1:02.496	5681488	52	9	00:01:38.228	1
24518	1025	8	51	7	15	13	13	13	53	+1:08.910	5687902	51	13	00:01:38.589	1
24519	1025	842	5	10	16	14	14	14	53	+1:10.076	5689068	51	14	00:01:38.606	1
24520	1025	841	51	99	12	15	15	15	53	+1:13.346	5692338	51	16	00:01:38.696	1
24521	1025	9	3	88	18	\N	R	16	28	\N	\N	24	19	00:01:42.327	23
24522	1025	847	3	63	17	\N	R	17	27	\N	\N	18	18	00:01:41.705	23
24523	1025	20	6	5	3	\N	R	18	26	\N	\N	16	10	00:01:38.245	75
24524	1025	817	4	3	10	\N	R	19	24	\N	\N	22	17	00:01:41.284	4
24525	1025	154	210	8	8	\N	R	20	0	\N	\N	\N	0	\N	4
24526	1026	822	131	77	3	1	1	1	52	1:21:46.755	4906755	49	4	00:01:31.862	1
24527	1026	20	6	5	1	2	2	2	52	+13.343	4920098	38	5	00:01:32.122	1
24528	1026	1	131	44	4	3	3	3	52	+13.858	4920613	45	1	00:01:30.983	1
24529	1026	848	9	23	6	4	4	4	52	+59.537	4966292	36	8	00:01:32.775	1
24530	1026	832	1	55	7	5	5	5	52	+1:09.101	4975856	46	12	00:01:33.563	1
24531	1026	844	6	16	2	6	6	6	51	\N	\N	48	11	00:01:33.481	11
24532	1026	842	5	10	9	7	7	7	51	\N	\N	48	2	00:01:31.611	11
24533	1026	815	211	11	17	8	8	8	51	\N	\N	43	17	00:01:35.321	11
24534	1026	840	211	18	12	9	9	9	51	\N	\N	46	7	00:01:32.621	11
24535	1026	826	5	26	14	10	10	10	51	\N	\N	47	15	00:01:34.921	11
24536	1026	846	1	4	8	11	11	11	51	\N	\N	26	14	00:01:34.713	11
24537	1026	8	51	7	13	12	12	12	51	\N	\N	47	10	00:01:33.239	11
24538	1026	154	210	8	10	13	13	13	51	\N	\N	31	13	00:01:34.116	11
24539	1026	841	51	99	11	14	14	14	51	\N	\N	50	9	00:01:33.19	11
24540	1026	825	210	20	19	15	15	15	51	\N	\N	18	16	00:01:34.988	11
24541	1026	847	3	63	18	16	16	16	50	\N	\N	51	6	00:01:32.369	12
24542	1026	9	3	88	0	16	16	17	50	\N	\N	49	3	00:01:31.732	12
24543	1026	830	9	33	5	\N	R	18	14	\N	\N	27	18	00:01:35.458	23
24544	1026	817	4	3	16	\N	D	19	51	\N	\N	44	19	00:01:36.332	2
24545	1026	807	4	27	15	\N	D	20	51	\N	\N	10	20	00:01:37.249	2
24546	1027	1	131	44	3	1	1	1	71	1:36:48.904	5808904	66	4	00:01:19.461	1
24547	1027	20	6	5	2	2	2	2	71	+1.766	5810670	68	3	00:01:19.381	1
24548	1027	822	131	77	6	3	3	3	71	+3.553	5812457	66	5	00:01:19.494	1
24549	1027	844	6	16	1	4	4	4	71	+6.368	5815272	53	1	00:01:19.232	1
24550	1027	848	9	23	5	5	5	5	71	+21.399	5830303	48	2	00:01:19.325	1
24551	1027	830	9	33	4	6	6	6	71	+1:08.807	5877711	65	11	00:01:20.406	1
24552	1027	815	211	11	11	7	7	7	71	+1:13.819	5882723	70	12	00:01:20.485	1
24553	1027	817	4	3	13	8	8	8	71	+1:14.924	5883828	53	9	00:01:20.146	1
24554	1027	842	5	10	10	9	9	9	70	\N	\N	53	6	00:01:19.53	11
24555	1027	807	4	27	12	10	10	10	70	\N	\N	59	14	00:01:20.791	11
24556	1027	826	5	26	9	11	11	11	70	\N	\N	48	7	00:01:19.905	11
24557	1027	840	211	18	16	12	12	12	70	\N	\N	68	15	00:01:20.922	11
24558	1027	832	1	55	7	13	13	13	70	\N	\N	66	10	00:01:20.311	11
24559	1027	841	51	99	15	14	14	14	70	\N	\N	65	16	00:01:21.014	11
24560	1027	825	210	20	17	15	15	15	69	\N	\N	53	20	00:01:21.682	12
24561	1027	847	3	63	19	16	16	16	69	\N	\N	69	17	00:01:21.286	12
24562	1027	154	210	8	18	17	17	17	69	\N	\N	68	18	00:01:21.581	12
24563	1027	9	3	88	20	18	18	18	69	\N	\N	63	13	00:01:20.696	12
24564	1027	8	51	7	14	\N	R	19	58	\N	\N	55	8	00:01:20.082	25
24565	1027	846	1	4	8	\N	R	20	48	\N	\N	46	19	00:01:21.643	54
24626	1041	822	131	77	1	1	1	1	71	1:30:55.739	5455739	68	2	00:01:07.657	1
24566	1028	822	131	77	1	1	1	1	56	1:33:55.653	5635653	37	2	00:01:36.957	1
24567	1028	1	131	44	5	2	2	2	56	+4.148	5639801	26	7	00:01:38.446	1
24568	1028	830	9	33	3	3	3	3	56	+5.002	5640655	42	5	00:01:38.214	1
24569	1028	844	6	16	4	4	4	4	56	+52.239	5687892	44	1	00:01:36.169	1
24570	1028	848	9	23	6	5	5	5	56	+1:18.038	5713691	42	3	00:01:38.029	1
24571	1028	817	4	3	9	6	6	6	56	+1:30.366	5726019	28	14	00:01:40.564	1
24572	1028	846	1	4	8	7	7	7	56	+1:30.764	5726417	44	4	00:01:38.074	1
24573	1028	832	1	55	7	8	8	8	55	\N	\N	44	15	00:01:40.844	11
24574	1028	807	4	27	11	9	9	9	55	\N	\N	47	6	00:01:38.437	11
24575	1028	815	211	11	0	10	10	10	55	\N	\N	34	11	00:01:40.165	11
24576	1028	8	51	7	17	11	11	11	55	\N	\N	46	9	00:01:39.608	11
24577	1028	826	5	26	13	12	12	12	55	\N	\N	41	8	00:01:38.969	11
24578	1028	840	211	18	14	13	13	13	55	\N	\N	42	13	00:01:40.38	11
24579	1028	841	51	99	16	14	14	14	55	\N	\N	41	10	00:01:39.964	11
24580	1028	154	210	8	15	15	15	15	55	\N	\N	52	18	00:01:41.27	11
24581	1028	842	5	10	10	16	16	16	54	\N	\N	31	16	00:01:40.85	22
24582	1028	847	3	63	18	17	17	17	54	\N	\N	54	17	00:01:41.239	12
24583	1028	825	210	20	12	18	18	18	52	\N	\N	42	12	00:01:40.347	23
24584	1028	9	3	88	19	\N	R	19	31	\N	\N	22	20	00:01:43.83	44
24585	1028	20	6	5	2	\N	R	20	7	\N	\N	6	19	00:01:42.165	22
24586	1029	830	9	33	1	1	1	1	71	1:33:14.678	5594678	61	2	00:01:10.862	1
24587	1029	842	5	10	6	2	2	2	71	+6.077	5600755	65	9	00:01:12.425	1
24588	1029	832	1	55	20	3	3	3	71	+8.896	5603574	63	16	00:01:13.158	1
24589	1029	8	51	7	8	4	4	4	71	+9.452	5604130	65	15	00:01:13.135	1
24590	1029	841	51	99	12	5	5	5	71	+10.201	5604879	49	14	00:01:13.02	1
24591	1029	817	4	3	11	6	6	6	71	+10.541	5605219	44	11	00:01:12.733	1
24592	1029	1	131	44	3	7	7	7	71	+11.139	5605817	46	3	00:01:11.082	1
24593	1029	846	1	4	10	8	8	8	71	+11.204	5605882	63	7	00:01:12.328	1
24594	1029	815	211	11	15	9	9	9	71	+11.529	5606207	64	12	00:01:12.84	1
24595	1029	826	5	26	16	10	10	10	71	+11.931	5606609	49	8	00:01:12.385	1
24596	1029	825	210	20	9	11	11	11	71	+12.732	5607410	65	17	00:01:13.262	1
24597	1029	847	3	63	18	12	12	12	71	+13.599	5608277	57	19	00:01:13.752	1
24598	1029	154	210	8	7	13	13	13	71	+14.247	5608925	29	18	00:01:13.619	1
24599	1029	848	9	23	5	14	14	14	71	+14.927	5609605	52	4	00:01:11.087	1
24600	1029	807	4	27	13	15	15	15	71	+18.059	5612737	64	13	00:01:12.934	1
24601	1029	9	3	88	19	16	16	16	70	\N	\N	63	20	00:01:14.553	11
24602	1029	20	6	5	2	17	17	17	65	\N	\N	51	5	00:01:11.384	4
24603	1029	844	6	16	14	18	18	18	65	\N	\N	63	6	00:01:11.423	4
24604	1029	840	211	18	17	19	19	19	65	\N	\N	65	10	00:01:12.603	22
24605	1029	822	131	77	4	\N	R	20	51	\N	\N	43	1	00:01:10.698	131
24606	1030	1	131	44	1	1	1	1	55	1:34:05.715	5645715	53	1	00:01:39.283	1
24607	1030	830	9	33	2	2	2	2	55	+16.772	5662487	55	5	00:01:41.119	1
24608	1030	844	6	16	3	3	3	3	55	+43.435	5689150	44	4	00:01:40.442	1
24609	1030	822	131	77	20	4	4	4	55	+44.379	5690094	31	2	00:01:39.715	1
24610	1030	20	6	5	4	5	5	5	55	+1:04.357	5710072	55	3	00:01:40.128	1
24611	1030	848	9	23	5	6	6	6	55	+1:09.205	5714920	49	8	00:01:42.219	1
24612	1030	815	211	11	10	7	7	7	54	\N	\N	39	11	00:01:42.639	11
24613	1030	846	1	4	6	8	8	8	54	\N	\N	50	12	00:01:43.026	11
24614	1030	826	5	26	13	9	9	9	54	\N	\N	42	9	00:01:42.222	11
24615	1030	832	1	55	8	10	10	10	54	\N	\N	43	7	00:01:41.294	11
24616	1030	817	4	3	7	11	11	11	54	\N	\N	51	6	00:01:41.19	11
24617	1030	807	4	27	9	12	12	12	54	\N	\N	52	16	00:01:43.274	11
24618	1030	8	51	7	17	13	13	13	54	\N	\N	25	14	00:01:43.142	11
24619	1030	825	210	20	14	14	14	14	54	\N	\N	22	19	00:01:43.79	11
24620	1030	154	210	8	15	15	15	15	54	\N	\N	33	18	00:01:43.666	11
24621	1030	841	51	99	16	16	16	16	54	\N	\N	28	15	00:01:43.256	11
24622	1030	847	3	63	18	17	17	17	54	\N	\N	50	13	00:01:43.074	11
24623	1030	842	5	10	11	18	18	18	53	\N	\N	53	10	00:01:42.414	12
24624	1030	9	3	88	19	19	19	19	53	\N	\N	51	20	00:01:44.5	12
24625	1030	840	211	18	12	\N	R	20	45	\N	\N	25	17	00:01:43.326	23
24627	1041	844	6	16	7	2	2	2	71	+2.700	5458439	64	4	00:01:07.901	1
24628	1041	846	1	4	3	3	3	3	71	+5.491	5461230	71	1	00:01:07.475	1
24629	1041	1	131	44	5	4	4	4	71	+5.689	5461428	67	3	00:01:07.712	1
24630	1041	832	1	55	8	5	5	5	71	+8.903	5464642	63	5	00:01:07.974	1
24631	1041	815	211	11	6	6	6	6	71	+15.092	5470831	63	6	00:01:08.305	1
24632	1041	842	213	10	12	7	7	7	71	+16.682	5472421	64	11	00:01:09.025	1
24633	1041	839	4	31	14	8	8	8	71	+17.456	5473195	64	10	00:01:08.932	1
24634	1041	841	51	99	18	9	9	9	71	+21.146	5476885	70	9	00:01:08.796	1
24635	1041	20	6	5	11	10	10	10	71	+24.545	5480284	71	8	00:01:08.623	1
24636	1041	849	3	6	20	11	11	11	71	+31.650	5487389	63	16	00:01:09.662	1
24637	1041	826	213	26	13	12	12	12	69	\N	\N	50	13	00:01:09.135	22
24638	1041	848	9	23	4	13	13	13	67	\N	\N	50	7	00:01:08.432	40
24639	1041	8	51	7	19	\N	R	14	53	\N	\N	48	12	00:01:09.031	36
24640	1041	847	3	63	17	\N	R	15	49	\N	\N	49	14	00:01:09.317	32
24641	1041	154	210	8	15	\N	R	16	49	\N	\N	46	17	00:01:10.228	23
24642	1041	825	210	20	16	\N	R	17	24	\N	\N	23	20	00:01:10.72	23
24643	1041	840	211	18	9	\N	R	18	20	\N	\N	4	18	00:01:10.326	5
24644	1041	817	4	3	10	\N	R	19	17	\N	\N	8	19	00:01:10.61	25
24645	1041	830	9	33	2	\N	R	20	11	\N	\N	5	15	00:01:09.351	40
24646	1042	1	131	44	1	1	1	1	71	1:22:50.683	4970683	68	3	00:01:06.719	1
24647	1042	822	131	77	4	2	2	2	71	+13.719	4984402	62	7	00:01:07.534	1
24648	1042	830	9	33	2	3	3	3	71	+33.698	5004381	70	2	00:01:06.145	1
24649	1042	848	9	23	6	4	4	4	71	+44.400	5015083	67	6	00:01:07.299	1
24650	1042	846	1	4	9	5	5	5	71	+1:01.470	5032153	66	5	00:01:07.193	1
24651	1042	815	211	11	17	6	6	6	71	+1:02.387	5033070	68	4	00:01:07.188	1
24652	1042	840	211	18	12	7	7	7	71	+1:02.453	5033136	65	10	00:01:07.833	1
24653	1042	817	4	3	8	8	8	8	71	+1:02.591	5033274	65	9	00:01:07.832	1
24654	1042	832	1	55	3	9	9	9	70	\N	\N	68	1	00:01:05.619	11
24655	1042	826	213	26	13	10	10	10	70	\N	\N	60	13	00:01:08.378	11
24656	1042	8	51	7	16	11	11	11	70	\N	\N	57	14	00:01:08.382	11
24657	1042	825	210	20	15	12	12	12	70	\N	\N	69	11	00:01:08.009	11
24658	1042	154	210	8	0	13	13	13	70	\N	\N	69	12	00:01:08.047	11
24659	1042	841	51	99	19	14	14	14	70	\N	\N	54	15	00:01:08.512	11
24660	1042	842	213	10	7	15	15	15	70	\N	\N	69	8	00:01:07.827	11
24661	1042	847	3	63	11	16	16	16	69	\N	\N	36	16	00:01:08.601	12
24662	1042	849	3	6	18	17	17	17	69	\N	\N	68	17	00:01:08.806	12
24663	1042	839	4	31	5	\N	R	18	25	\N	\N	22	18	00:01:09.321	25
24664	1042	844	6	16	14	\N	R	19	4	\N	\N	3	19	00:01:35.379	130
24665	1042	20	6	5	10	\N	R	20	1	\N	\N	\N	0	\N	130
\.


--
-- Data for Name: lookup_status_gp; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.lookup_status_gp (status_id, status_desc) FROM stdin;
1	Finished
2	Disqualified
3	Accident
4	Collision
5	Engine
6	Gearbox
7	Transmission
8	Clutch
9	Hydraulics
10	Electrical
11	+1 Lap
12	+2 Laps
13	+3 Laps
14	+4 Laps
15	+5 Laps
16	+6 Laps
17	+7 Laps
18	+8 Laps
19	+9 Laps
20	Spun off
21	Radiator
22	Suspension
23	Brakes
24	Differential
25	Overheating
26	Mechanical
27	Tyre
28	Driver Seat
29	Puncture
30	Driveshaft
31	Retired
32	Fuel pressure
33	Front wing
34	Water pressure
35	Refuelling
36	Wheel
37	Throttle
38	Steering
39	Technical
40	Electronics
41	Broken wing
42	Heat shield fire
43	Exhaust
44	Oil leak
45	+11 Laps
46	Wheel rim
47	Water leak
48	Fuel pump
49	Track rod
50	+17 Laps
51	Oil pressure
128	+42 Laps
53	+13 Laps
54	Withdrew
55	+12 Laps
56	Engine fire
129	Engine misfire
58	+26 Laps
59	Tyre puncture
60	Out of fuel
61	Wheel nut
62	Not classified
63	Pneumatics
64	Handling
65	Rear wing
66	Fire
67	Wheel bearing
68	Physical
69	Fuel system
70	Oil line
71	Fuel rig
72	Launch control
73	Injured
74	Fuel
75	Power loss
76	Vibrations
77	107% Rule
78	Safety
79	Drivetrain
80	Ignition
81	Did not qualify
82	Injury
83	Chassis
84	Battery
85	Stalled
86	Halfshaft
87	Crankshaft
88	+10 Laps
89	Safety concerns
90	Not restarted
91	Alternator
92	Underweight
93	Safety belt
94	Oil pump
95	Fuel leak
96	Excluded
97	Did not prequalify
98	Injection
99	Distributor
100	Driver unwell
101	Turbo
102	CV joint
103	Water pump
104	Fatal accident
105	Spark plugs
106	Fuel pipe
107	Eye injury
108	Oil pipe
109	Axle
110	Water pipe
111	+14 Laps
112	+15 Laps
113	+25 Laps
114	+18 Laps
115	+22 Laps
116	+16 Laps
117	+24 Laps
118	+29 Laps
119	+23 Laps
120	+21 Laps
121	Magneto
122	+44 Laps
123	+30 Laps
124	+19 Laps
125	+46 Laps
126	Supercharger
127	+20 Laps
130	Collision damage
131	Power Unit
132	ERS
133	+49 Laps
134	+38 Laps
135	Brake duct
136	Seat
137	Damage
\.


--
-- Data for Name: pointsmark; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pointsmark (pid, points) FROM stdin;
1	25
2	18
3	15
4	12
5	10
6	8
7	6
8	4
9	2
10	1
\.


--
-- Name: fact_race_gp fact_race_gp_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_race_gp
    ADD CONSTRAINT fact_race_gp_pkey PRIMARY KEY (race_id);


--
-- Name: lookup_status_gp lookup_status_gp_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lookup_status_gp
    ADD CONSTRAINT lookup_status_gp_pkey PRIMARY KEY (status_id);


--
-- Name: fact_circuits pk_circuit_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_circuits
    ADD CONSTRAINT pk_circuit_id PRIMARY KEY (circuit_id);


--
-- Name: fact_constructors pk_constructor_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_constructors
    ADD CONSTRAINT pk_constructor_id PRIMARY KEY (constructor_id);


--
-- Name: fact_drivers pk_driver_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_drivers
    ADD CONSTRAINT pk_driver_id PRIMARY KEY (driver_id);


--
-- Name: fact_session_race_results pk_result_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_session_race_results
    ADD CONSTRAINT pk_result_id PRIMARY KEY (result_id);


--
-- Name: pointsmark pointsmark_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pointsmark
    ADD CONSTRAINT pointsmark_pkey PRIMARY KEY (pid);


--
-- Name: fact_race_gp fk_circuit_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_race_gp
    ADD CONSTRAINT fk_circuit_id FOREIGN KEY (circuit_id) REFERENCES public.fact_circuits(circuit_id);


--
-- Name: fact_session_race_results fk_constructor_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_session_race_results
    ADD CONSTRAINT fk_constructor_id FOREIGN KEY (constructor_id) REFERENCES public.fact_constructors(constructor_id);


--
-- Name: fact_session_race_results fk_driver_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_session_race_results
    ADD CONSTRAINT fk_driver_id FOREIGN KEY (driver_id) REFERENCES public.fact_drivers(driver_id);


--
-- Name: fact_session_race_results fk_race_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_session_race_results
    ADD CONSTRAINT fk_race_id FOREIGN KEY (race_id) REFERENCES public.fact_race_gp(race_id);


--
-- PostgreSQL database dump complete
--

