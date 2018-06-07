<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet id="stylesheet"
                version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
		xmlns:perlfuncs="urn:perlfuncs"
		xmlns:str="http://exslt.org/strings"
		extension-element-prefixes="str"
		>

<xsl:template match="xsl:stylesheet" />
  
<xsl:template match="/">
  <html>
    <head>
      <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
      <meta http-equiv="Cache-Control" content="no-store" />
      <title><xsl:value-of select="$header"/></title>
      <style type="text/css">
	.fieldname { color: #187ee6; font-size:smaller; vertical-align: text-top; padding: 0; margin: 0; }
	.sectiontitle { color: #00a688; font-size: larger; font-variant: small-caps; }
	.item { border: solid 1px #dddddd; margin: 0px 0px 1px 0px; padding: 0px 1px 0px 1px; background: #fff; }

	body { font-size: 9pt; font-family: serif; border: none; }
	h2 { font-size: 16pt; background: #ffffff; color: #187ee6; }
	h3 { font-size: 12px; color: #0d4680; margin: 1em 0em 0em 0em; padding: 0em 1em 0em 0em; }
	ul { display: inline; margin: 0; padding: 0; list-style-type: none; }
	li { display: inline-block; padding: .0em 0em 0em 0em; margin: 0; color: #000; background-color: #fefefe; }

	table { page-break-inside:auto; border: solid black 1px; width: 100%; border-collapse: collapse; empty-cells: show; }
	th { font-weight: bold; font-size: 9pt; border: solid black 1px; }
	td { font-size: 9pt; border: solid black 1px;}
	tr { page-break-inside:avoid; page-break-after:auto; }
      </style>
    </head>
    <body>
	<h2><xsl:value-of select="$header"/></h2>

	<xsl:if test="/opt/anon[typeName='webforms.WebForm']">
	    <h3>Logins</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='webforms.WebForm']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountUS']">
	    <h3>Bank Accounts</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountUS']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountAU']">
	    <h3>Bank Accounts (AU)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountAU']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountCA']">
	    <h3>Bank Accounts (CA)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountCA']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountCH']">
	    <h3>Bank Accounts (CH)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountCH']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountDE']">
	    <h3>Bank Accounts (DE)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountDE']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.financial.BankAccountUK']">
	    <h3>Bank Accounts (UK)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.BankAccountUK']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.financial.CreditCard']">
	    <h3>Credit Cards</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.financial.CreditCard']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.government.SsnUS']">
	    <h3>Social Security</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.government.SsnUS']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='identities.Identity']">
	    <h3>Identity</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='identities.Identity']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.computer.License']">
	    <h3>Software</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.computer.License']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.computer.Database']">
	    <h3>Database</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.computer.Database']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.government.DriversLicense']">
	    <h3>Drivers License</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.government.DriversLicense']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.Email.v2']">
	    <h3>Email</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.Email.v2']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.FTP']">
	    <h3>FTP</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.FTP']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.DotMac']">
	    <h3>MobileMe</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.DotMac']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.Email']">
	    <h3>Email (legacy)</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.Email']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.GenericAccount']">
	    <h3>Generic Account</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.GenericAccount']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.InstantMessenger']">
	    <h3>Instant Messenger</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.InstantMessenger']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.ISP']">
	    <h3>Internet Provider</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.ISP']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.iTunes']">
	    <h3>iTunes</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.iTunes']"/>
	</xsl:if>
	<xsl:if test="/opt/anon[typeName='wallet.onlineservices.AmazonS3']">
	    <h3>Amazon S3</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.onlineservices.AmazonS3']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.membership.Membership']">
	    <h3>Membership</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.membership.Membership']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.government.HuntingLicense']">
	    <h3>Outdoor License</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.government.HuntingLicense']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.government.Passport']">
	    <h3>Passport</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.government.Passport']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='passwords.Password']">
	    <h3>Password</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='passwords.Password']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.membership.RewardProgram']">
	    <h3>Reward Program</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.membership.RewardProgram']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.computer.UnixServer']">
	    <h3>Server</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.computer.UnixServer']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='wallet.computer.UnixServer']">
	    <h3>Wireless Router</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='wallet.computer.UnixServer']"/>
	</xsl:if>

	<xsl:if test="/opt/anon[typeName='securenotes.SecureNote']">
	    <h3>Secure Notes</h3>
	    <xsl:apply-templates select="/opt/anon[typeName='securenotes.SecureNote']"/>
	</xsl:if>

    </body>
  </html>
</xsl:template>

<xsl:template match="anon">
    <div class="item">
	<ul>
	    <xsl:apply-templates select="title" />
	    <xsl:apply-templates select="secureContents/fields" />
	    <xsl:apply-templates select="secureContents/URLs" />
	    <xsl:apply-templates select="secureContents/sections" />
	    <xsl:apply-templates select="openContents[tags]" />
	    <xsl:apply-templates select="secureContents/notesPlain" />
	    <xsl:apply-templates select="secureContents" />
	    <xsl:apply-templates select="createdAt" />
	    <xsl:apply-templates select="updatedAt" />
	</ul>
    </div>
</xsl:template>

<xsl:template match="title">
    <li>
    <span class="fieldname">title: </span>
	<xsl:apply-templates />
    </li>
</xsl:template>

<xsl:template match="createdAt">
    <li>
    <span class="fieldname">created: </span>
	<xsl:value-of select="perlfuncs:epoch2date(.)" />
    </li>
</xsl:template>

<xsl:template match="updatedAt">
    <li>
    <span class="fieldname">modified: </span>
	<xsl:value-of select="perlfuncs:epoch2date(.)" />
    </li>
</xsl:template>

<!-- openContents -->
<xsl:template match="openContents">
    <xsl:if test="tags">
	<li>
	    <span class="fieldname">tags: </span>
	    <xsl:for-each select="tags">
		<xsl:value-of select="." />
		<xsl:if test="position() != last()">, </xsl:if>
	    </xsl:for-each>
	</li>
    </xsl:if>
</xsl:template>

<!-- secureContents -->
<xsl:template match="secureContents/fields">
    <xsl:for-each select=".">
	<xsl:if test="value">
		<xsl:choose>
		    <xsl:when test="../../typeName='webforms.WebForm'">
			<xsl:if test="designation">
			    <li>
				<span class="fieldname"><xsl:value-of select="designation" />: </span>
				<xsl:value-of select = "value" />
			    </li>
			</xsl:if>
		    </xsl:when>
		    <xsl:otherwise>
			<li>
			    <span class="fieldname"><xsl:value-of select="name" />: </span>
			    <xsl:value-of select = "value" />
			</li>
		    </xsl:otherwise>
		</xsl:choose>
	</xsl:if>
    </xsl:for-each>
</xsl:template>

<xsl:template match="secureContents/URLs">
    <xsl:for-each select=".">
	<li>
	    <xsl:choose>
		<xsl:when test="label != ''">
		    <span class="fieldname"><xsl:value-of select = "label" />: </span>
		</xsl:when>
		<xsl:otherwise>
		    <span class="fieldname">url: </span>
		</xsl:otherwise>
	    </xsl:choose>
	    <xsl:value-of select = "url" />
	</li>
    </xsl:for-each>
</xsl:template>

<xsl:template match="secureContents/sections">
    <xsl:if test="title != ''">
	<xsl:if test="*[3]">
	    <span class="sectiontitle">&lt;<xsl:value-of select="title" />&gt; </span>
	</xsl:if>
    </xsl:if>

    <xsl:for-each select="fields">
	<xsl:if test="v != ''" >
	    <li>
		<span class="fieldname">
		    <xsl:choose>
			<xsl:when test="t='verification number'">CVV</xsl:when>
			<xsl:when test="t='cash withdrawal limit'">w/d limit</xsl:when>
			<xsl:when test="t='interest rate'">int rate</xsl:when>
			<xsl:otherwise><xsl:value-of select = "t" /></xsl:otherwise>
		    </xsl:choose>
		    <xsl:text>:</xsl:text>
		    <xsl:text disable-output-escaping="yes">&amp;</xsl:text>nbsp;
		</span>
		<xsl:choose>
		    <xsl:when test="k='date'"><xsl:value-of select="perlfuncs:epoch2date(./v, 1)" /></xsl:when>
		    <xsl:when test="k='monthYear'"><xsl:value-of select="perlfuncs:monthYear(./v)" /></xsl:when>
		    <xsl:when test="k='address'"><xsl:value-of select="perlfuncs:address2str(./v)" /></xsl:when>
		    <xsl:otherwise><xsl:value-of select = "v" /></xsl:otherwise>
		</xsl:choose>
	    </li>
	</xsl:if>
    </xsl:for-each>
</xsl:template>

<xsl:template match="secureContents">
    <xsl:if test="Linked_Items">
	<li>
	    <span class="fieldname">related_items: </span>
	    <xsl:for-each select="Linked_Items">
		<xsl:value-of select="." />
		<xsl:if test="position() != last()">, </xsl:if>
	    </xsl:for-each>
	</li>
    </xsl:if>
</xsl:template>

<xsl:template match="secureContents/notesPlain">
    <li>
	<span class="fieldname">notes: </span>
	<xsl:value-of select="translate(., '&#10;', '&#x23CE;')" />
    </li>
</xsl:template>
</xsl:stylesheet>
