<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:gmd="http://www.isotc211.org/2005/gmd"
  xmlns:gco="http://www.isotc211.org/2005/gco"
  xmlns:srv="http://www.isotc211.org/2005/srv"
  xmlns:gmx="http://www.isotc211.org/2005/gmx"
  xmlns:xlink="http://www.w3.org/1999/xlink" 
  xmlns:gml="http://www.opengis.net/gml" 
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:ns3="http://www.w3.org/2001/SMIL20/" 
  xmlns:ns9="http://www.w3.org/2001/SMIL20/Language" 
  xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" 
  xmlns:dct="http://purl.org/dc/terms/" 
  xmlns:ogc="http://www.opengis.net/ogc" 
  xmlns:ows="http://www.opengis.net/ows" 
  xmlns:gn="http://www.fao.org/geonetwork" 
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:solr="java:org.daobs.index.SolrRequestBean"
  exclude-result-prefixes="#all"
  version="2.0">

  <xsl:variable name="harvester" as="element()"
                select="/harvestedContent/harvester"/>

  <xsl:variable name="dateFormat" as="xs:string"
                select="'[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01]Z'"/>

  <xsl:variable name="separator" as="xs:string"
                select="'|'"/>



  <xsl:template match="/">
    <!-- Add a Solr document -->
    <add>
      <!-- For any ISO19139 records in the input XML document
      Some records from IS do not have record identifier. Ignore them.
      -->
      <xsl:variable name="records" select="//gmd:MD_Metadata[gmd:fileIdentifier/gco:CharacterString != '']"/>

      <xsl:for-each select="$records">
        <!-- Main variables for the document -->
        <xsl:variable name="identifier" as="xs:string"
                      select="gmd:fileIdentifier/gco:CharacterString[. != '']"/>

        <xsl:variable name="mainLanguage" as="xs:string?"
                      select="gmd:language/gco:CharacterString[normalize-space(.) != '']|
                          gmd:language/gmd:LanguageCode/
                            @codeListValue[normalize-space(.) != '']"/>

        <xsl:variable name="otherLanguages" as="attribute()*"
                      select="gmd:locale/gmd:PT_Locale/
                            gmd:languageCode/gmd:LanguageCode/
                              @codeListValue[normalize-space(.) != '']"/>

        <!-- Record is dataset if no hierarchyLevel -->
        <xsl:variable name="isDataset" as="xs:boolean"
                      select="
                          count(gmd:hierarchyLevel[gmd:MD_ScopeCode/@codeListValue='dataset']) > 0 or
                          count(gmd:hierarchyLevel) = 0"/>
        <xsl:variable name="isService" as="xs:boolean"
                      select="
                          count(gmd:hierarchyLevel[gmd:MD_ScopeCode/@codeListValue='service']) > 0"/>

        <xsl:message>#<xsl:value-of select="$identifier"/></xsl:message>

        <!-- Create a first document representing the main record. -->
        <doc>
          <field name="documentType">metadata</field>
          <field name="id"><xsl:value-of select="$identifier"/></field>
          <field name="metadataIdentifier"><xsl:value-of select="$identifier"/></field>

          <!-- Harvester details -->
          <field name="territory"><xsl:value-of select="$harvester/territory"/></field>
          <field name="harvesterId"><xsl:value-of select="$harvester/url"/></field>
          <field name="harvestedDate">
            <xsl:value-of select="if ($harvester/date)
                                  then $harvester/date
                                  else format-dateTime(current-dateTime(), $dateFormat)"/>
          </field>


          <!-- Indexing record information -->
          <!-- # Date -->
          <!-- TODO improve date formatting maybe using Joda parser -->
          <xsl:for-each select="gmd:dateStamp/*">
            <field name="dateStamp">
              <xsl:value-of select="if (name() = 'gco:Date' or string-length(.) = 10)
                                    then concat(., 'T00:00:00Z')
                                    else (
                                      if (ends-with(., 'Z'))
                                      then .
                                      else concat(., 'Z')
                                    )"/>
            </field>
          </xsl:for-each>


          <!-- # Languages -->
          <field name="mainLanguage"><xsl:value-of select="$mainLanguage"/></field>

          <xsl:for-each select="$otherLanguages">
            <field name="otherLanguage"><xsl:value-of select="."/></field>
          </xsl:for-each>


          <!-- # Resource type -->
          <xsl:choose>
            <xsl:when test="$isDataset">
              <field name="resourceType">dataset</field>
            </xsl:when>
            <xsl:otherwise>
              <xsl:for-each select="gmd:hierarchyLevel/gmd:MD_ScopeCode/
                                  @codeListValue[normalize-space(.) != '']">
                <field name="resourceType"><xsl:value-of select="."/></field>
              </xsl:for-each>
            </xsl:otherwise>
          </xsl:choose>


          <!-- Indexing metadata contact -->
          <xsl:apply-templates mode="index-contact" select="gmd:contact">
            <xsl:with-param name="fieldSuffix" select="''"/>
          </xsl:apply-templates>


          <!-- Indexing resource information
          TODO: Should we support multiple identification in the same record
          eg. nl db60a314-5583-437d-a2ff-1e59cc57704e
          -->
          <xsl:for-each select="gmd:identificationInfo[1]/*">
            <xsl:for-each select="gmd:citation/gmd:CI_Citation">
              <field name="resourceTitle">
                <xsl:value-of select="gmd:title/gco:CharacterString/text()"/>
              </field>

              <xsl:for-each select="gmd:date/gmd:CI_Date">
                <xsl:variable name="dateType"
                              select="gmd:dateType/gmd:CI_DateTypeCode/@codeListValue"
                              as="xs:string?"/>
                <xsl:variable name="date"
                              select="string(gmd:date/gco:Date|gmd:date/gco:DateTime)"/>
                <field name="{$dateType}DateForResource"><xsl:value-of select="$date"/></field>
                <field name="{$dateType}YearForResource"><xsl:value-of select="substring($date, 0, 5)"/></field>
                <field name="{$dateType}MonthForResource"><xsl:value-of select="substring($date, 0, 8)"/></field>
              </xsl:for-each>
            </xsl:for-each>

            <field name="resourceAbstract">
              <xsl:value-of select="gmd:abstract/gco:CharacterString/text()"/>
            </field>


            <!-- Indexing resource contact -->
            <xsl:apply-templates mode="index-contact"
                                 select="gmd:pointOfContact">
              <xsl:with-param name="fieldSuffix" select="'ForResource'"/>
            </xsl:apply-templates>


            <xsl:for-each select="gmd:presentationForm/gmd:CI_PresentationFormCode/@codeListValue[. != '']">
              <field name="presentationForm"><xsl:value-of select="."/></field>
            </xsl:for-each>


            <xsl:for-each select="gmd:graphicOverview/gmd:MD_BrowseGraphic/
                                  gmd:fileName/gco:CharacterString[. != '']">
              <field name="overviewUrl"><xsl:value-of select="."/></field>
            </xsl:for-each>

            <xsl:for-each select="gmd:language/gco:CharacterString|gmd:language/gmd:LanguageCode/@codeListValue">
              <field name="resourceLanguage"><xsl:value-of select="."/></field>
            </xsl:for-each>



            <!-- TODO: create specific INSPIRE template or mode -->
            <!-- INSPIRE themes -->
            <xsl:for-each
                    select="gmd:descriptiveKeywords
                       /gmd:MD_Keywords[contains(
                         gmd:thesaurusName/gmd:CI_Citation/
                           gmd:title/gco:CharacterString/text(),
                           'GEMET - INSPIRE themes')]
                      /gmd:keyword/gco:CharacterString">

              <xsl:variable name="inspireTheme" as="xs:string"
                            select="solr:analyzeField('inspireTheme_syn', text())"/>

              <field name="inspireTheme_syn"><xsl:value-of select="text()"/></field>
              <field name="inspireTheme"><xsl:value-of select="$inspireTheme"/></field>

              <!--
              WARNING: Here we only index the first keyword in order
              to properly compute one INSPIRE annex.
              -->
              <xsl:if test="position() = 1">
                <field name="inspireAnnex">
                  <xsl:value-of select="solr:analyzeField('inspireAnnex_syn', $inspireTheme)"/>
                </field>
              </xsl:if>
            </xsl:for-each>

            <field name="numberOfInspireTheme"><xsl:value-of select="count(gmd:descriptiveKeywords
                       /gmd:MD_Keywords[contains(
                         gmd:thesaurusName/gmd:CI_Citation/
                           gmd:title/gco:CharacterString/text(),
                           'GEMET - INSPIRE themes')]
                      /gmd:keyword)"/></field>

            <xsl:for-each
                    select="gmd:descriptiveKeywords/gmd:MD_Keywords/gmd:keyword/gco:CharacterString">
              <field name="tag"><xsl:value-of select="text()"/></field>
            </xsl:for-each>

            <xsl:for-each select="gmd:topicCategory/gmd:MD_TopicCategoryCode">
              <field name="topic"><xsl:value-of select="."/></field>
              <!-- TODO: Get translation ? -->
            </xsl:for-each>



            <xsl:for-each select="gmd:spatialResolution/gmd:MD_Resolution">
              <xsl:for-each select="gmd:equivalentScale/gmd:MD_RepresentativeFraction/gmd:denominator/gco:Integer[. != '']">
                <field name="resolutionScaleDenominator"><xsl:value-of select="."/></field>
              </xsl:for-each>

              <xsl:for-each select="gmd:distance/gco:Distance[. != '']">
                <field name="resolutionDistance"><xsl:value-of select="concat(., @uom)"/></field>
              </xsl:for-each>
            </xsl:for-each>

            <xsl:for-each select="gmd:spatialRepresentationType/gmd:MD_SpatialRepresentationTypeCode/@codeListValue[. != '']">
              <field name="spatialRepresentationType"><xsl:value-of select="."/></field>
            </xsl:for-each>



            <xsl:for-each select="gmd:resourceConstraints">
              <xsl:for-each select="*/gmd:accessConstraints/gmd:MD_RestrictionCode/@codeListValue[. != '']">
                <field name="accessConstraints"><xsl:value-of select="."/></field>
              </xsl:for-each>
              <xsl:for-each select="*/gmd:otherConstraints/gco:CharacterString[. != '']">
                <field name="otherConstraints"><xsl:value-of select="."/></field>
              </xsl:for-each>
              <xsl:for-each select="*/gmd:classification/gmd:MD_ClassificationCode/@codeListValue[. != '']">
                <field name="constraintClassification"><xsl:value-of select="."/></field>
              </xsl:for-each>
              <xsl:for-each select="*/gmd:useLimitation/gco:CharacterString[. != '']">
                <field name="useLimitation"><xsl:value-of select="."/></field>
              </xsl:for-each>
            </xsl:for-each>




            <xsl:for-each select="*/gmd:EX_Extent">

              <xsl:for-each select="gmd:geographicElement/gmd:EX_GeographicDescription/
                gmd:geographicIdentifier/gmd:MD_Identifier/
                gmd:code/gco:CharacterString[normalize-space(.) != '']">
                <field name="geoTag"><xsl:value-of select="."/></field>
              </xsl:for-each>

              <!-- TODO: index bbox -->
            </xsl:for-each>


            <!-- Service information -->
            <xsl:for-each select="srv:serviceType/gco:LocalName">
              <field name="serviceType"><xsl:value-of select="text()"/></field>
              <xsl:variable name="inspireServiceType" as="xs:string"
                            select="solr:analyzeField(
                            'inspireServiceType', text(),
                            'query',
                            'org.apache.lucene.analysis.miscellaneous.KeepWordFilter',
                            0)"/>
              <xsl:if test="$inspireServiceType != ''">
                <field name="inspireServiceType"><xsl:value-of select="lower-case($inspireServiceType)"/></field>
              </xsl:if>
              <xsl:if test="following-sibling::srv:serviceTypeVersion">
                <field name="serviceTypeAndVersion">
                  <xsl:value-of select="concat(
                            text(),
                            $separator,
                            following-sibling::srv:serviceTypeVersion/gco:CharacterString/text())"/>
                </field>
              </xsl:if>
            </xsl:for-each>
          </xsl:for-each>







          <xsl:for-each select="gmd:referenceSystemInfo/gmd:MD_ReferenceSystem">
            <xsl:for-each select="gmd:referenceSystemIdentifier/gmd:RS_Identifier">
              <xsl:variable name="crs" select="gmd:code/gco:CharacterString"/>

              <xsl:if test="$crs != ''">
                <field name="coordinateSystem"><xsl:value-of select="$crs"/></field>
              </xsl:if>
            </xsl:for-each>
          </xsl:for-each>





          <!-- INSPIRE Conformity -->
          <xsl:variable name="specificationTitle" as="xs:string"
                        select="'1089/2010'"/>

          <!-- TODO : check on publication date and full spec name ?
          Commission Regulation (EU) No 1089/2010 of 23 November 2010 implementing Directive 2007/2/EC of the European Parliament and of the Council as regards interoperability of spatial data sets and services
          -->
          <xsl:variable name="results" as="element()*"
                        select="gmd:dataQualityInfo/*/gmd:report/*/gmd:result[
                                  contains(*/gmd:specification/gmd:CI_Citation/
                                    gmd:title/gco:CharacterString, $specificationTitle)]"/>

          <xsl:for-each select="$results">
            <field name="inspireConformResource"><xsl:value-of select="*/gmd:pass/gco:Boolean"/></field>
          </xsl:for-each>

          <field name="lineage"><xsl:value-of select="gmd:dataQualityInfo/*/
                                  gmd:lineage/gmd:LI_Lineage/
                                    gmd:statement/gco:CharacterString"/></field>


          <!-- Service/dataset relation. Create document for the association.
           This could be used to retrieve :
          {!child of=documentType:metadata}+documentType:metadata +id:9940c446-6fd4-4ab3-a4de-7d0ee028a8d1
          {!child of=documentType:metadata}+documentType:metadata +resourceType:service +serviceType:view
          {!child of=documentType:metadata}+documentType:metadata +resourceType:service +serviceType:download
           -->
          <xsl:for-each select="gmd:identificationInfo/srv:SV_ServiceIdentification/srv:operatesOn">
            <xsl:variable name="associationType" select="'operatesOn'"/>
            <xsl:variable name="serviceType" select="../srv:serviceType/gco:LocalName"/>
            <!--<xsl:variable name="relatedTo" select="@uuidref"/>-->
            <xsl:variable name="relatedTo">
              <xsl:if test="@xlink:href != ''">
                <xsl:analyze-string select="@xlink:href"
                                    regex=".*id=([\w-]*).*">
                  <xsl:matching-substring>
                    <xsl:value-of select="regex-group(1)"/>
                  </xsl:matching-substring>
                </xsl:analyze-string>
              </xsl:if>
            </xsl:variable>
            <field name="recordOperateOn"><xsl:value-of select="$relatedTo"/></field>

            <doc>
              <field name="id"><xsl:value-of
                      select="concat('association', $identifier,
                $associationType, $relatedTo)"/></field>
              <field name="metadataIdentifier"><xsl:value-of select="$identifier"/></field>
              <field name="documentType">association</field>
              <field name="record"><xsl:value-of select="$identifier"/></field>
              <field name="associationType"><xsl:value-of select="$associationType"/></field>
              <field name="relatedTo"><xsl:value-of select="$relatedTo"/></field>
            </doc>
            <doc>
              <field name="id"><xsl:value-of
                      select="concat('association',
                $associationType, $relatedTo)"/></field>
              <field name="metadataIdentifier"><xsl:value-of select="$identifier"/></field>
              <field name="documentType">association2</field>
              <field name="record"><xsl:value-of select="$identifier"/></field>
              <field name="associationType"><xsl:value-of select="concat($associationType, $serviceType)"/></field>
              <field name="relatedTo"><xsl:value-of select="$relatedTo"/></field>
            </doc>
          </xsl:for-each>
        </doc>


        <!-- Create or update child document and register service relation
        in recordOperatedBy field and als associated resources.

         TODO: Some countries are using uuidref to store
         resource identifier and not metadata identifier. -->
        <xsl:for-each select="gmd:identificationInfo/srv:SV_ServiceIdentification/srv:operatesOn">
          <xsl:message>## child record <xsl:value-of select="@xlink:href"/> </xsl:message>

          <!--
          uuiref store resource identifier and not metadata identifier.
              <xsl:variable name="relatedTo" select="@uuidref"/>
          -->
          <xsl:variable name="relatedTo">
            <xsl:if test="@xlink:href != ''">
              <xsl:analyze-string select="@xlink:href"
                                  regex=".*id=([\w-]*).*">
                <xsl:matching-substring>
                  <xsl:value-of select="regex-group(1)"/>
                </xsl:matching-substring>
              </xsl:analyze-string>
            </xsl:if>
          </xsl:variable>
          <xsl:message>## child record <xsl:value-of select="$relatedTo"/> </xsl:message>

          <xsl:choose>
            <xsl:when test="$relatedTo">
              <doc>
                <field name="id"><xsl:value-of select="$relatedTo"/></field>
                <field name="metadataIdentifier" update="set"><xsl:value-of select="$relatedTo"/></field>
                <field name="recordOperatedBy" update="add"><xsl:value-of select="$identifier"/></field>
                <xsl:for-each select="../srv:serviceType/gco:LocalName">
                  <field name="recordOperatedByType" update="add"><xsl:value-of select="."/></field>
                </xsl:for-each>
              </doc>
            </xsl:when>
            <xsl:otherwise>
              <xsl:message>Failed to extract metadata identifier from @uuidref or xlink:href <xsl:value-of select="@xlink:href"/></xsl:message>
            </xsl:otherwise>
          </xsl:choose>

        </xsl:for-each>
      </xsl:for-each>
    </add>
  </xsl:template>


  <xsl:template mode="index-contact" match="*">
    <xsl:param name="fieldSuffix" select="''" as="xs:string"/>

    <xsl:variable name="organisationName"
                  select="*/gmd:organisationName/(gco:CharacterString|gmx:Anchor)"
                  as="xs:string*"/>
    <xsl:variable name="role"
                  select="*/gmd:role/*/@codeListValue"
                  as="xs:string?"/>
    <xsl:if test="normalize-space($organisationName) != ''">
      <field name="Org{$fieldSuffix}"><xsl:value-of select="$organisationName"/></field>
      <field name="{$role}Org{$fieldSuffix}"><xsl:value-of select="$organisationName"/></field>
    </xsl:if>
    <field name="contact{$fieldSuffix}">{
      org:"<xsl:value-of select="replace($organisationName, '&quot;', '\\&quot;')"/>",
      role:"<xsl:value-of select="$role"/>"
      }
    </field>
  </xsl:template>
</xsl:stylesheet>