{{ config(enabled=var('ad_reporting__tiktok_ads_enabled', true),
     partition_by={
      "field": "updated_at", 
      "data_type": "datetime",
      "granularity": "day"
    }


) }}

with base as (

    select *
    from {{ ref('stg_tiktok_ads__ad_history_tmp') }}
), 

fields as (

    select
        {{
            fivetran_utils.fill_staging_columns(
                source_columns=adapter.get_columns_in_relation(ref('stg_tiktok_ads__ad_history_tmp')),
                staging_columns=get_ad_history_columns()
            )
        }}

    
        {{ fivetran_utils.source_relation(
            union_schema_variable='tiktok_ads_union_schemas', 
            union_database_variable='tiktok_ads_union_databases') 
        }}

    from base
), 
smartplus as (
    select *,
        row_number() over (
            partition by smart_plus_ad_id 
            order by updated_at desc
        ) = 1 as is_most_recent_record
    from `tyson-reporting-prod.mother_ny_tf_tiktok_ads_raw_prod.smart_plus_ad_history`
),

smartplus_latest as (
    select *
    from smartplus 
    where is_most_recent_record = true
),
final as (

    select
        source_relation,  
        ad_id,
        --cast(updated_at as {{ dbt.type_timestamp() }}) as updated_at,
        DATETIME(TIMESTAMP(fields.updated_at), "America/Chicago") as updated_at,
        fields.adgroup_id as ad_group_id,
        fields.advertiser_id,
        fields.campaign_id,
        case 
            when fields.smart_plus_ad_id is not null then s.ad_name
            else fields.ad_name
        end as ad_name,
        fields.call_to_action,
        fields.click_tracking_url,
        fields.impression_tracking_url,
        {{ dbt.split_part('landing_page_url', "'?'", 1) }} as base_url,
        {{ dbt_utils.get_url_host('landing_page_url') }} as url_host,
        '/' || {{ dbt_utils.get_url_path('landing_page_url') }} as url_path,
        {{ tiktok_ads_source.tiktok_ads_extract_url_parameter('landing_page_url', 'utm_source') }} as utm_source,
        {{ tiktok_ads_source.tiktok_ads_extract_url_parameter('landing_page_url', 'utm_medium') }} as utm_medium,
        {{ tiktok_ads_source.tiktok_ads_extract_url_parameter('landing_page_url', 'utm_campaign') }} as utm_campaign,
        {{ tiktok_ads_source.tiktok_ads_extract_url_parameter('landing_page_url', 'utm_content') }} as utm_content,
        {{ tiktok_ads_source.tiktok_ads_extract_url_parameter('landing_page_url', 'utm_term') }} as utm_term,
        landing_page_url,
        row_number() over (partition by source_relation, ad_id order by fields.updated_at desc) = 1 as is_most_recent_record
    from fields
    left join  smartplus_latest s
    on safe_cast(fields.smart_plus_ad_id as INT64) = s.smart_plus_ad_id
    
)

select * 
from final
